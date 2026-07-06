function Get-CISBaselineTemplateNameSet {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$Platform = @('All'),

        [Parameter(Mandatory)]
        [hashtable]$PlatformValueMapping
    )

    $templateNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $templateFiles = Get-ChildItem -Path $Path -Filter "*.json" -File -Recurse

    foreach ($templateFile in $templateFiles) {
        try {
            $templateContent = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
            if ($Platform -and $Platform -notcontains 'All') {
                $mappedPlatforms = @(Resolve-CISBaselineTemplatePlatform -TemplateContent $templateContent -TemplateFile $templateFile -BaselinePath $Path -PlatformValueMapping $PlatformValueMapping)
                if ($mappedPlatforms.Count -eq 0 -or -not ($mappedPlatforms | Where-Object { $_ -in $Platform })) {
                    continue
                }
            }

            $templateName = if ($templateContent.name) { $templateContent.name } elseif ($templateContent.displayName) { $templateContent.displayName } else { $null }
            if ($templateName) {
                [void]$templateNames.Add($templateName)
            }
        } catch {
            Write-Verbose "Failed to parse CIS template for delete scoping: $($templateFile.FullName)"
        }
    }

    return , $templateNames
}
