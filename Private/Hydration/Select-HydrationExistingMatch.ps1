function Select-HydrationExistingMatch {
    <#
    .SYNOPSIS
        Selects the existing Graph object that matches a template name.
    .DESCRIPTION
        Canonical implementation of the dual-lookup match policy: candidates are
        matched on the prefixed name or the legacy unprefixed name. When
        -PreferTagged is set, a candidate carrying the hydration kit marker wins
        over any untagged match. Returns $null when nothing matches.
    .PARAMETER Candidates
        Objects returned from a Graph list/filter call.
    .PARAMETER Name
        Preferred (prefixed) display name.
    .PARAMETER LegacyName
        Optional legacy unprefixed name accepted as a match.
    .PARAMETER NameProperty
        Property holding the object name. Defaults to displayName.
    .PARAMETER PreferTagged
        Prefer candidates tagged with the hydration kit marker.
    .OUTPUTS
        psobject or $null
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Candidates = @(),

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$LegacyName,

        [Parameter()]
        [string]$NameProperty = 'displayName',

        [Parameter()]
        [switch]$PreferTagged
    )

    $acceptLegacy = -not [string]::IsNullOrWhiteSpace($LegacyName) -and $LegacyName -ne $Name
    $nameMatches = @($Candidates | Where-Object {
            $candidateName = $_.$NameProperty
            $candidateName -eq $Name -or ($acceptLegacy -and $candidateName -eq $LegacyName)
        })

    if ($nameMatches.Count -eq 0) {
        return $null
    }

    if ($PreferTagged) {
        foreach ($candidate in $nameMatches) {
            if (Test-HydrationKitObject -Description $candidate.description -ObjectName $candidate.$NameProperty) {
                return $candidate
            }
        }
    }

    return $nameMatches[0]
}
