function Get-IntuneWinPackagingCapability {
    <#
    .SYNOPSIS
        Reports cross-platform primitives available for .intunewin packaging.
    .DESCRIPTION
        Validates the .NET APIs a repo-owned .intunewin packager will need so future work
        can stay PowerShell 7 cross-platform instead of depending on IntuneWinAppUtil.exe.
    .OUTPUTS
        PSCustomObject describing packaging capability status.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $capabilityChecks = [ordered]@{
        ZipArchive      = $null -ne ('System.IO.Compression.ZipArchive' -as [type])
        Aes             = $null -ne ('System.Security.Cryptography.Aes' -as [type])
        HmacSha256      = $null -ne ('System.Security.Cryptography.HMACSHA256' -as [type])
        Sha256          = $null -ne ('System.Security.Cryptography.SHA256' -as [type])
        XmlDocument     = $null -ne ('System.Xml.XmlDocument' -as [type])
        FileCompression = $null -ne ('System.IO.Compression.CompressionLevel' -as [type])
    }

    $missingCapabilities = $capabilityChecks.GetEnumerator() |
        Where-Object { -not $_.Value } |
        Select-Object -ExpandProperty Key
    $supportsCrossPlatformIntuneWin = $missingCapabilities.Count -eq 0

    $platform = if ($IsWindows) {
        'Windows'
    } elseif ($IsMacOS) {
        'macOS'
    } elseif ($IsLinux) {
        'Linux'
    } else {
        'Unknown'
    }

    return [PSCustomObject]@{
        Platform                       = $platform
        PowerShellEdition              = $PSVersionTable.PSEdition
        PowerShellVersion              = $PSVersionTable.PSVersion.ToString()
        SupportsCrossPlatformIntuneWin = $supportsCrossPlatformIntuneWin
        MissingCapabilities            = @($missingCapabilities)
        Capabilities                   = [PSCustomObject]$capabilityChecks
    }
}
