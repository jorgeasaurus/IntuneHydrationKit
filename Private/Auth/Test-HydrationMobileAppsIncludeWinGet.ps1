function Test-HydrationMobileAppsIncludeWinGet {
    <#
    .SYNOPSIS
        Determines whether the selected mobile app configuration includes WinGet app templates.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [hashtable]$Configuration = @{},

        [Parameter()]
        [string[]]$Platforms = @('All')
    )

    $selectedPlatforms = @($Platforms | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($selectedPlatforms.Count -eq 0) {
        $selectedPlatforms = @('All')
    }

    if (-not ($selectedPlatforms -contains 'All' -or $selectedPlatforms -contains 'Windows')) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($Configuration.presetId)) {
        return $true
    }

    $requestedTemplateIds = @($Configuration.templateIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requestedTemplateIds.Count -eq 0) {
        return $true
    }

    $winGetAppTemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath 'MobileApps/Windows/WinGet/Apps'
    if (-not (Test-Path -Path $winGetAppTemplatePath)) {
        return $false
    }

    $winGetTemplateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($templateFile in Get-ChildItem -Path $winGetAppTemplatePath -Filter '*.json' -File) {
        [void]$winGetTemplateIds.Add([System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name))
    }

    foreach ($templateId in $requestedTemplateIds) {
        if ($winGetTemplateIds.Contains([string]$templateId)) {
            return $true
        }
    }

    return $false
}
