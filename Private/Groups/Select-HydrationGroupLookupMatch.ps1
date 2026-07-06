function Select-HydrationGroupLookupMatch {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$LookupResult,

        [Parameter(Mandatory)]
        [object]$GroupDefinition,

        [Parameter()]
        [switch]$PreferHydrationMarker
    )

    return Select-HydrationExistingMatch `
        -Candidates $LookupResult.value `
        -Name $GroupDefinition.displayName `
        -LegacyName $GroupDefinition._OriginalDisplayName `
        -PreferTagged:$PreferHydrationMarker
}
