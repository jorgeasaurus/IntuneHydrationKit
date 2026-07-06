function Test-HydrationTemplateNameMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [System.Collections.Generic.HashSet[string]]$KnownTemplateNames,

        [Parameter()]
        [string]$Prefix = $(if ([string]::IsNullOrEmpty($script:ImportPrefix)) { '[IHD] ' } else { $script:ImportPrefix })
    )

    if (-not $KnownTemplateNames -or $KnownTemplateNames.Count -eq 0) {
        return $false
    }

    $escapedPrefix = [regex]::Escape($Prefix)
    $unprefixedName = $Name -replace "^$escapedPrefix", ''

    return $KnownTemplateNames.Contains($Name) -or $KnownTemplateNames.Contains($unprefixedName)
}
