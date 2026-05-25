function Format-WinGetInstallerSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [psobject]$Installer
    )

    if (-not $Installer) {
        return 'None'
    }

    $installerFileName = $null
    if (-not [string]::IsNullOrWhiteSpace($Installer.InstallerUrl)) {
        try {
            $installerFileName = [System.IO.Path]::GetFileName(([System.Uri]$Installer.InstallerUrl).AbsolutePath)
        } catch {
            $installerFileName = $Installer.InstallerUrl
        }
    }

    return "Architecture='$($Installer.Architecture)', Scope='$($Installer.Scope)', Locale='$($Installer.InstallerLocale)', Type='$($Installer.InstallerType)', File='$installerFileName'"
}
