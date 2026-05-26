function Get-MobileAppTemplateNameSet {
    <#
    .SYNOPSIS
        Builds a HashSet of display names from mobile app template files.
    .DESCRIPTION
        Reads each template file, extracts displayName, and returns a
        case-insensitive HashSet containing the current suffixed name plus
        supported raw and legacy-prefixed variants. Used for idempotency and
        template-scoped deletes.
    .PARAMETER TemplateFiles
        Array of FileInfo objects representing the template files to read.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TemplateFiles
    )

    $displayNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($templateFile in $TemplateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            if (-not [string]::IsNullOrWhiteSpace($template.displayName)) {
                $templateDisplayName = [string]$template.displayName
                foreach ($nameVariant in Get-HydrationMobileAppNameVariant -DisplayName $templateDisplayName) {
                    [void]$displayNames.Add($nameVariant)
                }
            }
        } catch {
            Write-Verbose "Skipping template display-name lookup for '$($templateFile.FullName)': $($_.Exception.Message)"
        }
    }

    return $displayNames
}
