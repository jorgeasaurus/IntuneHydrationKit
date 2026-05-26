function Get-HydrationMobileAppBaseName {
    <#
    .SYNOPSIS
        Returns the raw app name used to derive hydration mobile app display names.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return $DisplayName
    }

    $suffix = ' - [IHD]'
    $prefix = [string]$script:ImportPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        $prefix = '[IHD] '
    }

    $baseName = $DisplayName.Trim()
    if ($baseName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $baseName = $baseName.Substring($prefix.Length).TrimStart()
    }

    if ($baseName.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $baseName = $baseName.Substring(0, $baseName.Length - $suffix.Length).TrimEnd()
    }

    if ([string]::IsNullOrWhiteSpace($baseName)) {
        return $DisplayName
    }

    return $baseName
}
