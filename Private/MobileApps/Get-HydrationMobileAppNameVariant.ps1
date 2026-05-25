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
    $escapedPrefix = [regex]::Escape($script:ImportPrefix)

    $normalizedName = $rawName -replace "^$escapedPrefix", ''
    $normalizedName = if ($normalizedName.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedName.Substring(0, $normalizedName.Length - $suffix.Length)
    } else {
        $normalizedName
    }

    $currentName = Get-HydrationMobileAppDisplayName -DisplayName $normalizedName
    $legacyPrefixedName = "$($script:ImportPrefix)$normalizedName"
    $rawNameWithoutSuffix = if ($rawName.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rawName.Substring(0, $rawName.Length - $suffix.Length)
    } else {
        $rawName
    }

    @(
        $currentName
        $rawName
        $legacyPrefixedName
        $normalizedName
        $rawNameWithoutSuffix
    ) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
}
