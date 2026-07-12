function Resolve-HydrationMarkedDeleteCandidate {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Notes,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [System.Collections.Generic.HashSet[string]]$KnownTemplateNames,

        [Parameter()]
        [string]$FullObjectUri,

        [Parameter()]
        [switch]$MobileAppName
    )

    $deleteDecision = Resolve-HydrationDeleteDecision `
        -Name $Name `
        -Description $Description `
        -Notes $Notes `
        -KnownTemplateNames $KnownTemplateNames `
        -MobileAppName:$MobileAppName

    if (-not $deleteDecision.NeedsFullObject -or [string]::IsNullOrWhiteSpace($FullObjectUri)) {
        return $deleteDecision
    }

    try {
        $fullObject = Invoke-MgGraphRequest -Method GET -Uri $FullObjectUri -ErrorAction Stop
        return Resolve-HydrationDeleteDecision `
            -Name $Name `
            -Description $fullObject.description `
            -Notes $fullObject.notes `
            -KnownTemplateNames $KnownTemplateNames `
            -MobileAppName:$MobileAppName
    } catch {
        Write-Verbose "Could not verify hydration marker for '$Name' from $FullObjectUri`: $_"
        return $deleteDecision
    }
}
