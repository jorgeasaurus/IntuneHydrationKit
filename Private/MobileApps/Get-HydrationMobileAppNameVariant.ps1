function Get-HydrationMobileAppNameVariant {
    <#
    .SYNOPSIS
        Returns all supported Intune Hydration Kit mobile app display-name variants.
    .DESCRIPTION
        Centralizes the current suffix format and legacy raw/prefixed formats used
        for idempotency and template-scoped deletes.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return @()
    }

    $suffix = ' - [IHD]'
    $rawName = $DisplayName.Trim()
    $baseName = Get-HydrationMobileAppBaseName -DisplayName $rawName

    $currentName = Get-HydrationMobileAppDisplayName -DisplayName $baseName
    $legacyPrefixedName = "$($script:ImportPrefix)$baseName"
    $rawNameWithoutSuffix = $rawName
    if ($rawNameWithoutSuffix.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rawNameWithoutSuffix = $rawNameWithoutSuffix.Substring(0, $rawNameWithoutSuffix.Length - $suffix.Length).TrimEnd()
    }

    @(
        $currentName
        $rawName
        $legacyPrefixedName
        $baseName
        $rawNameWithoutSuffix
    ) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
}
