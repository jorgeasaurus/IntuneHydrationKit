function Resolve-MinimumSupportedOperatingSystem {
    <#
    .SYNOPSIS
        Maps Windows release labels to Graph minimum supported operating system payload keys.
    .PARAMETER Release
        The Windows release label (for example W10_22H2 or W11_24H2).
    .OUTPUTS
        hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$Release
    )

    $releaseMap = @{
        'W10_1607' = 'v10_1607'
        'W10_1703' = 'v10_1703'
        'W10_1709' = 'v10_1709'
        'W10_1803' = 'v10_1803'
        'W10_1809' = 'v10_1809'
        'W10_1903' = 'v10_1903'
        'W10_1909' = 'v10_1909'
        'W10_2004' = 'v10_2004'
        'W10_20H2' = 'v10_20H2'
        'W10_21H1' = 'v10_21H1'
        'W10_21H2' = 'v10_21H1'
        'W10_22H2' = 'v10_21H1'
        'W11_21H2' = 'v10_21H1'
        'W11_22H2' = 'v10_21H1'
        'W11_23H2' = 'v10_21H1'
        'W11_24H2' = 'v10_21H1'
    }

    $resolvedRelease = if ([string]::IsNullOrWhiteSpace($Release)) {
        'W10_1607'
    } else {
        $Release
    }

    $operatingSystemKey = if ($releaseMap.ContainsKey($resolvedRelease)) {
        $releaseMap[$resolvedRelease]
    } else {
        'v10_1607'
    }

    return @{ $operatingSystemKey = $true }
}
