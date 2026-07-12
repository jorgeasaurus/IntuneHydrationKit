function Get-HydrationBrowserAuthLogoDataUri {
    [CmdletBinding()]
    param()

    $logoPath = Join-Path $script:ModuleRoot 'media/IHTLogoClearLight.png'
    if (-not (Test-Path -Path $logoPath)) {
        return $null
    }

    $logoBytes = [System.IO.File]::ReadAllBytes($logoPath)
    return "data:image/png;base64,$([Convert]::ToBase64String($logoBytes))"
}
