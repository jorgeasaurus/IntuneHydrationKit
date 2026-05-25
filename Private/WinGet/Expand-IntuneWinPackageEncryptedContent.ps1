function Expand-IntuneWinPackageEncryptedContent {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IntuneWinPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $destinationDirectory = Split-Path -Path $DestinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -Path $destinationDirectory)) {
        $null = New-Item -Path $destinationDirectory -ItemType Directory -Force -ErrorAction Stop
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)
    try {
        $encryptedContentEntry = $archive.Entries |
            Where-Object { $_.Name -eq $FileName -or $_.FullName -like "*/$FileName" } |
            Select-Object -First 1

        if (-not $encryptedContentEntry) {
            throw "Encrypted content '$FileName' was not found in package '$IntuneWinPath'."
        }

        $entryStream = $encryptedContentEntry.Open()
        $fileStream = [System.IO.File]::Create($DestinationPath)
        try {
            $entryStream.CopyTo($fileStream)
        } finally {
            $fileStream.Dispose()
            $entryStream.Dispose()
        }

        return Get-Item -Path $DestinationPath
    } finally {
        $archive.Dispose()
    }
}
