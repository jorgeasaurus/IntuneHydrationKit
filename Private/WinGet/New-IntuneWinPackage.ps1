function New-IntuneWinPackage {
    <#
    .SYNOPSIS
        Builds a repo-owned .intunewin package.
    .DESCRIPTION
        Packages a source directory into the Intune portal-compatible .intunewin
        structure by zipping the source, encrypting the inner archive, generating a
        Detection.xml manifest, and producing the final outer package.
    .PARAMETER PackagingContext
        Packaging context returned by New-IntuneWinPackagingContext.
    .OUTPUTS
        PSCustomObject describing the generated package.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$PackagingContext
    )

    function ConvertTo-Base64 {
        param(
            [Parameter(Mandatory)]
            [byte[]]$Value
        )

        return [Convert]::ToBase64String($Value)
    }

    function Format-DetectionXml {
        param(
            [Parameter(Mandatory)]
            [string]$DisplayName,

            [Parameter(Mandatory)]
            [string]$InnerFileName,

            [Parameter(Mandatory)]
            [string]$SetupFile,

            [Parameter(Mandatory)]
            [int64]$UnencryptedContentSize,

            [Parameter(Mandatory)]
            [hashtable]$EncryptionInfo
        )

        $xml = [System.Xml.XmlDocument]::new()
        $applicationInfo = $xml.CreateElement('ApplicationInfo')
        $applicationInfo.SetAttribute('ToolVersion', '1.4.0.0')
        [void]$xml.AppendChild($applicationInfo)

        foreach ($node in @(
                @{ Name = 'Name'; Value = $DisplayName },
                @{ Name = 'UnencryptedContentSize'; Value = $UnencryptedContentSize },
                @{ Name = 'FileName'; Value = $InnerFileName },
                @{ Name = 'SetupFile'; Value = $SetupFile }
            )) {
            $element = $xml.CreateElement($node.Name)
            $element.InnerText = [string]$node.Value
            [void]$applicationInfo.AppendChild($element)
        }

        $encryptionElement = $xml.CreateElement('EncryptionInfo')
        foreach ($node in @(
                @{ Name = 'EncryptionKey'; Value = $EncryptionInfo.EncryptionKey },
                @{ Name = 'MacKey'; Value = $EncryptionInfo.MacKey },
                @{ Name = 'InitializationVector'; Value = $EncryptionInfo.InitializationVector },
                @{ Name = 'Mac'; Value = $EncryptionInfo.Mac },
                @{ Name = 'ProfileIdentifier'; Value = $EncryptionInfo.ProfileIdentifier },
                @{ Name = 'FileDigest'; Value = $EncryptionInfo.FileDigest },
                @{ Name = 'FileDigestAlgorithm'; Value = $EncryptionInfo.FileDigestAlgorithm }
            )) {
            $element = $xml.CreateElement($node.Name)
            $element.InnerText = [string]$node.Value
            [void]$encryptionElement.AppendChild($element)
        }
        [void]$applicationInfo.AppendChild($encryptionElement)

        $builder = [System.Text.StringBuilder]::new()
        $settings = [System.Xml.XmlWriterSettings]::new()
        $settings.Indent = $true
        $settings.IndentChars = '  '
        $settings.NewLineChars = "`r`n"
        $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
        $settings.OmitXmlDeclaration = $true

        $writer = [System.Xml.XmlWriter]::Create($builder, $settings)
        try {
            $xml.Save($writer)
        } finally {
            $writer.Dispose()
        }

        return $builder.ToString()
    }

    function Protect-ArchiveFile {
        param(
            [Parameter(Mandatory)]
            [string]$SourcePath,

            [Parameter(Mandatory)]
            [string]$DestinationPath
        )

        $encryptionAlgorithm = [System.Security.Cryptography.Aes]::Create()
        $macAlgorithm = [System.Security.Cryptography.Aes]::Create()
        $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
        $macLength = 32
        $sourceHashStream = $null
        $outputStream = $null
        $sourceStream = $null
        $cryptoStream = $null
        $hmac = $null

        try {
            $encryptionAlgorithm.GenerateKey()
            $macAlgorithm.GenerateKey()
            $initializationVector = $encryptionAlgorithm.IV

            $sourceHashStream = [System.IO.File]::OpenRead($SourcePath)
            $fileDigest = $hashAlgorithm.ComputeHash($sourceHashStream)
            $sourceHashStream.Dispose()
            $sourceHashStream = $null

            $outputStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $placeholderBytes = [byte[]]::new($macLength + $initializationVector.Length)
            $outputStream.Write($placeholderBytes, 0, $placeholderBytes.Length)

            $sourceStream = [System.IO.File]::OpenRead($SourcePath)
            $encryptor = $encryptionAlgorithm.CreateEncryptor($encryptionAlgorithm.Key, $initializationVector)
            $cryptoStream = [System.Security.Cryptography.CryptoStream]::new($outputStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write, $true)
            $sourceStream.CopyTo($cryptoStream)
            $cryptoStream.FlushFinalBlock()
            $cryptoStream.Dispose()
            $cryptoStream = $null
            $sourceStream.Dispose()
            $sourceStream = $null

            $outputStream.Position = $macLength
            $outputStream.Write($initializationVector, 0, $initializationVector.Length)
            $outputStream.Flush()

            $hmac = [System.Security.Cryptography.HMACSHA256]::new($macAlgorithm.Key)
            $outputStream.Position = $macLength
            $mac = $hmac.ComputeHash($outputStream)
            $hmac.Dispose()
            $hmac = $null

            $outputStream.Position = 0
            $outputStream.Write($mac, 0, $mac.Length)
            $outputStream.Flush()

            return @{
                EncryptionKey        = ConvertTo-Base64 -Value $encryptionAlgorithm.Key
                MacKey               = ConvertTo-Base64 -Value $macAlgorithm.Key
                InitializationVector = ConvertTo-Base64 -Value $initializationVector
                Mac                  = ConvertTo-Base64 -Value $mac
                ProfileIdentifier    = 'ProfileVersion1'
                FileDigest           = ConvertTo-Base64 -Value $fileDigest
                FileDigestAlgorithm  = 'SHA256'
            }
        } finally {
            if ($null -ne $hmac) {
                $hmac.Dispose()
            }

            if ($null -ne $cryptoStream) {
                $cryptoStream.Dispose()
            }

            if ($null -ne $sourceStream) {
                $sourceStream.Dispose()
            }

            if ($null -ne $sourceHashStream) {
                $sourceHashStream.Dispose()
            }

            if ($null -ne $outputStream) {
                $outputStream.Dispose()
            }

            $encryptionAlgorithm.Dispose()
            $macAlgorithm.Dispose()
            $hashAlgorithm.Dispose()
        }
    }

    function Add-ZipEntryFromFile {
        param(
            [Parameter(Mandatory)]
            [System.IO.Compression.ZipArchive]$Archive,

            [Parameter(Mandatory)]
            [string]$EntryName,

            [Parameter(Mandatory)]
            [string]$SourcePath
        )

        $entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::NoCompression)
        $entryStream = $entry.Open()
        try {
            $sourceStream = [System.IO.File]::OpenRead($SourcePath)
            try {
                $sourceStream.CopyTo($entryStream)
            } finally {
                $sourceStream.Dispose()
            }
        } finally {
            $entryStream.Dispose()
        }
    }

    function Add-ZipEntryFromText {
        param(
            [Parameter(Mandatory)]
            [System.IO.Compression.ZipArchive]$Archive,

            [Parameter(Mandatory)]
            [string]$EntryName,

            [Parameter(Mandatory)]
            [string]$Content
        )

        $entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::NoCompression)
        $entryStream = $entry.Open()
        $writer = [System.IO.StreamWriter]::new($entryStream, [System.Text.Encoding]::UTF8)
        try {
            $writer.Write($Content)
        } finally {
            $writer.Dispose()
            $entryStream.Dispose()
        }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (-not $PackagingContext.PackagingCapability -or -not $PackagingContext.PackagingCapability.SupportsCrossPlatformIntuneWin) {
        throw 'The current platform does not support repo-owned .intunewin packaging.'
    }

    if (-not (Test-Path -Path $PackagingContext.SourcePath -PathType Container)) {
        throw "Packaging source path not found: $($PackagingContext.SourcePath)"
    }

    if ([string]::IsNullOrWhiteSpace($PackagingContext.SetupFile)) {
        throw 'PackagingContext.SetupFile is required.'
    }

    if ([string]::IsNullOrWhiteSpace($PackagingContext.OutputPath)) {
        throw 'PackagingContext.OutputPath is required.'
    }

    $outputDirectory = Split-Path -Path $PackagingContext.OutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -Path $outputDirectory)) {
        $null = New-Item -Path $outputDirectory -ItemType Directory -Force -ErrorAction Stop
    }

    $workingRoot = Join-Path -Path $outputDirectory -ChildPath ('.winget-packaging-{0}' -f [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $workingRoot -ItemType Directory -Force -ErrorAction Stop

    $sourceArchivePath = Join-Path -Path $workingRoot -ChildPath 'source-content.zip'
    $encryptedArchivePath = Join-Path -Path $workingRoot -ChildPath 'IntunePackage.intunewin'
    $innerFileName = 'IntunePackage.intunewin'
    Write-Debug "Creating .intunewin package for '$($PackagingContext.PackageIdentifier)' version '$($PackagingContext.PackageVersion)'. SourcePath='$($PackagingContext.SourcePath)', SetupFile='$($PackagingContext.SetupFile)', OutputPath='$($PackagingContext.OutputPath)', WorkingRoot='$workingRoot'."

    try {
        if (Test-Path -Path $PackagingContext.OutputPath) {
            if (-not $PSCmdlet.ShouldProcess($PackagingContext.OutputPath, 'Overwrite existing .intunewin package')) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.OperationCanceledException]::new("Refused to overwrite existing package '$($PackagingContext.OutputPath)'."),
                    'IntuneWinPackageOverwriteDeclined',
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $PackagingContext.OutputPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            Write-Debug "Removing existing .intunewin output at '$($PackagingContext.OutputPath)'."
            Remove-Item -Path $PackagingContext.OutputPath -Force -ErrorAction Stop
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $PackagingContext.SourcePath,
            $sourceArchivePath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $false
        )

        $unencryptedContentSize = (Get-Item -Path $sourceArchivePath).Length
        Write-Debug "Created source archive '$sourceArchivePath' ($unencryptedContentSize bytes)."
        $encryptionInfo = Protect-ArchiveFile -SourcePath $sourceArchivePath -DestinationPath $encryptedArchivePath
        $encryptedContentSize = (Get-Item -Path $encryptedArchivePath).Length
        Write-Debug "Encrypted WinGet package payload to '$encryptedArchivePath' ($encryptedContentSize bytes)."
        $displayName = if ($PackagingContext.DisplayName) {
            $PackagingContext.DisplayName
        } elseif ($PackagingContext.PackageIdentifier) {
            $PackagingContext.PackageIdentifier
        } else {
            $PackagingContext.SetupFile
        }
        $detectionXml = Format-DetectionXml -DisplayName $displayName -InnerFileName $innerFileName -SetupFile $PackagingContext.SetupFile -UnencryptedContentSize $unencryptedContentSize -EncryptionInfo $encryptionInfo

        $fileStream = [System.IO.File]::Open($PackagingContext.OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $archive = [System.IO.Compression.ZipArchive]::new($fileStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
            try {
                Add-ZipEntryFromFile -Archive $archive -EntryName 'IntuneWinPackage/Contents/IntunePackage.intunewin' -SourcePath $encryptedArchivePath
                Add-ZipEntryFromText -Archive $archive -EntryName 'IntuneWinPackage/Metadata/Detection.xml' -Content $detectionXml
            } finally {
                $archive.Dispose()
            }
        } finally {
            $fileStream.Dispose()
        }

        $outputSize = (Get-Item -Path $PackagingContext.OutputPath).Length
        Write-Debug "Created final .intunewin package at '$($PackagingContext.OutputPath)' ($outputSize bytes)."

        return [PSCustomObject]@{
            OutputPath       = $PackagingContext.OutputPath
            FileName         = [System.IO.Path]::GetFileName($PackagingContext.OutputPath)
            SetupFile        = $PackagingContext.SetupFile
            UnencryptedSize  = $unencryptedContentSize
            EncryptionInfo   = [PSCustomObject]$encryptionInfo
            PackagingContext = $PackagingContext
        }
    } finally {
        if (Test-Path -Path $workingRoot) {
            Write-Debug "Removing packaging working directory '$workingRoot'."
            try {
                Remove-Item -Path $workingRoot -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Debug "Failed to remove packaging working directory '$workingRoot'. Error='$($_.Exception.Message)'."
            }
        }
    }
}
