function Get-IntuneWinPackageMetadata {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IntuneWinPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)
    try {
        $detectionXmlEntry = $archive.Entries |
            Where-Object { $_.FullName -match 'Detection\.xml$' } |
            Select-Object -First 1

        if (-not $detectionXmlEntry) {
            throw "Detection.xml not found in package '$IntuneWinPath'."
        }

        $metadataStream = $detectionXmlEntry.Open()
        $reader = [System.IO.StreamReader]::new($metadataStream)
        try {
            [xml]$metadataXml = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
            $metadataStream.Dispose()
        }

        $encryptionInfo = $metadataXml.ApplicationInfo.EncryptionInfo
        return [PSCustomObject]@{
            FileName             = [string]$metadataXml.ApplicationInfo.FileName
            SetupFile            = [string]$metadataXml.ApplicationInfo.SetupFile
            UnencryptedSize      = [int64]$metadataXml.ApplicationInfo.UnencryptedContentSize
            EncryptionKey        = [string]$encryptionInfo.EncryptionKey
            MacKey               = [string]$encryptionInfo.MacKey
            InitializationVector = [string]$encryptionInfo.InitializationVector
            Mac                  = [string]$encryptionInfo.Mac
            ProfileIdentifier    = [string]$encryptionInfo.ProfileIdentifier
            FileDigest           = [string]$encryptionInfo.FileDigest
            FileDigestAlgorithm  = [string]$encryptionInfo.FileDigestAlgorithm
        }
    } finally {
        $archive.Dispose()
    }
}
