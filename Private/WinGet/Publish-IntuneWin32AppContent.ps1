function Publish-IntuneWin32AppContent {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IntuneWinPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory,

        [Parameter()]
        [psobject]$Metadata,

        [Parameter()]
        [int]$TimeoutSeconds = 180
    )

    function Get-UploadUriForLogging {
        param(
            [Parameter(Mandatory)]
            [string]$Uri
        )

        return ($Uri -split '\?', 2)[0]
    }

    if (-not $Metadata) {
        $Metadata = Get-IntuneWinPackageMetadata -IntuneWinPath $IntuneWinPath
    }

    if (-not (Test-Path -Path $WorkingDirectory)) {
        $null = New-Item -Path $WorkingDirectory -ItemType Directory -Force
    }

    $encryptedContentPath = Join-Path -Path $WorkingDirectory -ChildPath $Metadata.FileName
    $contentVersionUri = "beta/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions"
    $appUri = "beta/deviceAppManagement/mobileApps/$AppId"
    Write-Debug "Publishing Win32 app content for AppId='$AppId'. IntuneWinPath='$IntuneWinPath', WorkingDirectory='$WorkingDirectory', PackageFileName='$($Metadata.FileName)'."

    $null = Expand-IntuneWinPackageEncryptedContent -IntuneWinPath $IntuneWinPath -FileName $Metadata.FileName -DestinationPath $encryptedContentPath
    try {
        Write-Debug "Expanded encrypted Win32 content to '$encryptedContentPath'."
        $contentVersionId = (Invoke-HydrationGraphRequest -Method POST -Uri $contentVersionUri -Body @{}).id
        Write-Debug "Created Win32 content version '$contentVersionId' for app '$AppId'."
        $encryptedSize = (Get-Item -Path $encryptedContentPath).Length
        $contentFileUri = "$contentVersionUri/$contentVersionId/files"
        $contentFile = Invoke-HydrationGraphRequest -Method POST -Uri $contentFileUri -Body @{
            '@odata.type' = '#microsoft.graph.mobileAppContentFile'
            name          = $Metadata.FileName
            size          = [int64]$Metadata.UnencryptedSize
            sizeEncrypted = [int64]$encryptedSize
            manifest      = $null
            isDependency  = $false
        }

        $contentFileId = $contentFile.id
        Write-Debug "Created Win32 content file '$contentFileId' for app '$AppId' (UnencryptedSize=$([int64]$Metadata.UnencryptedSize), EncryptedSize=$encryptedSize)."
        $fileInfo = Wait-IntuneWin32ContentState -AppId $AppId -ContentVersionId $contentVersionId -FileId $contentFileId -DesiredState 'azureStorageUriRequestSuccess' -TimeoutSeconds $TimeoutSeconds
        Write-Debug "Received Azure Storage upload target for content file '$contentFileId': '$(Get-UploadUriForLogging -Uri $fileInfo.azureStorageUri)'."

        $renewUploadAction = ${function:Get-IntuneWin32RenewedUploadUri}
        $renewUploadUri = {
            $renewedUploadUri = & $renewUploadAction -AppId $AppId -ContentVersionId $contentVersionId -ContentFileId $contentFileId -ContentFileUri $contentFileUri -TimeoutSeconds $TimeoutSeconds
            Write-Debug "Received renewed Azure Storage upload target for content file '$contentFileId': '$(Get-UploadUriForLogging -Uri $renewedUploadUri)'."
            return $renewedUploadUri
        }

        $uploadResult = Send-IntuneWinAzureStorageChunkedUpload -FilePath $encryptedContentPath -UploadUri $fileInfo.azureStorageUri -RenewUploadUri $renewUploadUri
        Write-Debug "Uploaded encrypted content for app '$AppId' using $($uploadResult.ChunkCount) chunk(s)."

        Invoke-HydrationGraphRequest -Method POST -Uri "$contentFileUri/$contentFileId/commit" -Body @{
            fileEncryptionInfo = @{
                encryptionKey        = $Metadata.EncryptionKey
                macKey               = $Metadata.MacKey
                initializationVector = $Metadata.InitializationVector
                mac                  = $Metadata.Mac
                profileIdentifier    = $Metadata.ProfileIdentifier
                fileDigest           = $Metadata.FileDigest
                fileDigestAlgorithm  = $Metadata.FileDigestAlgorithm
            }
        } | Out-Null
        Write-Debug "Submitted commit for content file '$contentFileId' in content version '$contentVersionId'."

        Wait-IntuneWin32ContentState -AppId $AppId -ContentVersionId $contentVersionId -FileId $contentFileId -DesiredState 'commitFileSuccess' -TimeoutSeconds $TimeoutSeconds | Out-Null
        Write-Debug "Win32 content file '$contentFileId' committed successfully."
        Invoke-HydrationGraphRequest -Method PATCH -Uri $appUri -Body @{
            '@odata.type'           = '#microsoft.graph.win32LobApp'
            committedContentVersion = $contentVersionId
        } | Out-Null
        Write-Debug "Marked app '$AppId' committedContentVersion as '$contentVersionId'."

        return [PSCustomObject]@{
            AppId              = $AppId
            ContentVersionId   = $contentVersionId
            ContentFileId      = $contentFileId
            PackagePath        = $encryptedContentPath
            EncryptedSize      = $encryptedSize
            UnencryptedSize    = [int64]$Metadata.UnencryptedSize
            UploadedChunkCount = $uploadResult.ChunkCount
        }
    } finally {
        if (Test-Path -Path $encryptedContentPath) {
            Write-Debug "Removing temporary encrypted content file '$encryptedContentPath'."
            Remove-Item -Path $encryptedContentPath -Force
        }
    }
}
