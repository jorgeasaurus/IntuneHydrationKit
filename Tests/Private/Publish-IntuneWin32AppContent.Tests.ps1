#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-IntuneWin32RenewedUploadUri.ps1
    . $PSScriptRoot/../../Private/WinGet/Publish-IntuneWin32AppContent.ps1
}

Describe 'Publish-IntuneWin32AppContent' {
    BeforeAll {
        . $PSScriptRoot/../../Private/WinGet/Get-IntuneWinPackageMetadata.ps1
        . $PSScriptRoot/../../Private/WinGet/Expand-IntuneWinPackageEncryptedContent.ps1
        . $PSScriptRoot/../../Private/Graph/Invoke-HydrationGraphRequest.ps1
        . $PSScriptRoot/../../Private/WinGet/Wait-IntuneWin32ContentState.ps1
        . $PSScriptRoot/../../Private/WinGet/Send-IntuneWinAzureStorageChunkedUpload.ps1
    }

    BeforeEach {
        $script:artifactRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/Publish-IntuneWin32AppContent'
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }

        $null = New-Item -Path $script:artifactRoot -ItemType Directory -Force
        'encrypted-content' | Set-Content -Path (Join-Path $script:artifactRoot 'app.bin')

        Mock Get-IntuneWinPackageMetadata {
            [pscustomobject]@{
                FileName             = 'app.bin'
                UnencryptedSize      = 321
                EncryptionKey        = 'enc'
                MacKey               = 'mackey'
                InitializationVector = 'iv'
                Mac                  = 'mac'
                ProfileIdentifier    = 'profile'
                FileDigest           = 'digest'
                FileDigestAlgorithm  = 'SHA256'
            }
        }

        Mock Expand-IntuneWinPackageEncryptedContent {
            Get-Item -Path (Join-Path $script:artifactRoot 'app.bin')
        }

        Mock Wait-IntuneWin32ContentState {
            [pscustomobject]@{
                uploadState     = $DesiredState
                azureStorageUri = 'https://storage.example/upload?sig=123'
            }
        }

        Mock Send-IntuneWinAzureStorageChunkedUpload {
            [pscustomobject]@{ ChunkCount = 3 }
        }

        Mock Invoke-HydrationGraphRequest {
            switch ($Uri) {
                'beta/deviceAppManagement/mobileApps/app-123/microsoft.graph.win32LobApp/contentVersions' {
                    return @{ id = 'content-version-1' }
                }
                'beta/deviceAppManagement/mobileApps/app-123/microsoft.graph.win32LobApp/contentVersions/content-version-1/files' {
                    return @{ id = 'file-1' }
                }
                default {
                    return @{}
                }
            }
        }
    }

    AfterEach {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
    }

    It 'Should create, upload, commit, and mark committed content' {
        $result = Publish-IntuneWin32AppContent -AppId 'app-123' -IntuneWinPath './fake.intunewin' -WorkingDirectory $script:artifactRoot

        $result.ContentVersionId | Should -Be 'content-version-1'
        $result.ContentFileId | Should -Be 'file-1'
        $result.UploadedChunkCount | Should -Be 3

        Should -Invoke Get-IntuneWinPackageMetadata -Exactly 1
        Should -Invoke Expand-IntuneWinPackageEncryptedContent -Exactly 1
        Should -Invoke Wait-IntuneWin32ContentState -Exactly 2
        Should -Invoke Send-IntuneWinAzureStorageChunkedUpload -Exactly 1
        Should -Invoke Invoke-HydrationGraphRequest -Exactly 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'beta/deviceAppManagement/mobileApps/app-123/microsoft.graph.win32LobApp/contentVersions/content-version-1/files/file-1/commit'
        }
        Should -Invoke Invoke-HydrationGraphRequest -Exactly 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'beta/deviceAppManagement/mobileApps/app-123'
        }
    }

    It 'Should wait for SAS renewal success before returning a renewed upload URI' {
        $script:renewedUploadUri = $null

        Mock Send-IntuneWinAzureStorageChunkedUpload {
            param(
                [string]$FilePath,
                [string]$UploadUri,
                [scriptblock]$RenewUploadUri
            )

            $script:renewedUploadUri = & $RenewUploadUri
            [pscustomobject]@{ ChunkCount = 3 }
        }

        Mock Wait-IntuneWin32ContentState {
            if ($DesiredState -eq 'azureStorageUriRenewalSuccess') {
                return [pscustomobject]@{
                    uploadState     = 'azureStorageUriRenewalSuccess'
                    azureStorageUri = 'https://storage.example/renewed?sig=456'
                }
            }

            [pscustomobject]@{
                uploadState     = $DesiredState
                azureStorageUri = 'https://storage.example/upload?sig=123'
            }
        }

        $null = Publish-IntuneWin32AppContent -AppId 'app-123' -IntuneWinPath './fake.intunewin' -WorkingDirectory $script:artifactRoot

        $script:renewedUploadUri | Should -Be 'https://storage.example/renewed?sig=456'

        Should -Invoke Invoke-HydrationGraphRequest -Exactly 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'beta/deviceAppManagement/mobileApps/app-123/microsoft.graph.win32LobApp/contentVersions/content-version-1/files/file-1/renewUpload'
        }
        Should -Invoke Wait-IntuneWin32ContentState -Exactly 1 -ParameterFilter {
            $DesiredState -eq 'azureStorageUriRenewalSuccess'
        }
    }
}
