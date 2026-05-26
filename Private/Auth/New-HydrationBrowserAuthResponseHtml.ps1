function New-HydrationBrowserAuthResponseHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Error')]
        [string]$Status,

        [string]$Message
    )

    $isSuccess = $Status -eq 'Success'
    $title = if ($isSuccess) { 'Authentication complete' } else { 'Authentication failed' }
    $defaultMessage = if ($isSuccess) {
        'You can close this tab and return to PowerShell.'
    } else {
        'Return to PowerShell for the full error.'
    }

    $logoDataUri = Get-HydrationBrowserAuthLogoDataUri
    $logoHtml = if ($logoDataUri) {
        "<img class='logo' src='$logoDataUri' alt='Intune Hydration Kit logo' />"
    } else {
        "<div class='mark'>IHK</div>"
    }

    $templatePath = Join-Path $script:ModuleRoot 'Private/Auth/Templates/BrowserAuthResponse.html'
    $template = [System.IO.File]::ReadAllText($templatePath)
    $replacements = @{
        '{{TITLE}}'       = [System.Net.WebUtility]::HtmlEncode($title)
        '{{MESSAGE}}'     = [System.Net.WebUtility]::HtmlEncode($(if ($Message) { $Message } else { $defaultMessage }))
        '{{ACCENT}}'      = if ($isSuccess) { '#21a366' } else { '#c2410c' }
        '{{STATUS_TEXT}}' = if ($isSuccess) { 'Connected' } else { 'Action needed' }
        '{{LOGO_HTML}}'   = $logoHtml
    }

    foreach ($key in $replacements.Keys) {
        $template = $template.Replace($key, $replacements[$key])
    }

    return $template
}
