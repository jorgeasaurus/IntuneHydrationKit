function Get-MobileAppTemplateNameSet {
    <#
    .SYNOPSIS
        Builds a HashSet of display names from mobile app template files.
    .DESCRIPTION
        Reads each template file, extracts the displayName, applies the
        hydration mobile-app display-name transformation (suffix), and
        returns a case-insensitive HashSet of
        the resulting names. Used for scoping deletion to known templates.
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
                [void]$displayNames.Add((Get-HydrationMobileAppDisplayName -DisplayName $templateDisplayName))
            }
        } catch {
            Write-Verbose "Skipping template display-name lookup for '$($templateFile.FullName)': $($_.Exception.Message)"
        }
    }

    return $displayNames
}
