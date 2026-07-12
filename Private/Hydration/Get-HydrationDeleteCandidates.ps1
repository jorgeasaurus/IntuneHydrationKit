function Get-HydrationDeleteCandidates {
    <#
    .SYNOPSIS
        Finds Graph objects that are safe delete candidates for hydration cleanup.
    .DESCRIPTION
        Enumerates objects from Graph list endpoints, keeps only objects created by the
        Intune Hydration Kit, and restricts matches to known template names.
        If a list response omits description or notes, the function performs a targeted
        GET for likely matches so the hydration marker can still be verified safely.
    .PARAMETER Endpoint
        One or more beta Graph endpoints to enumerate.
    .PARAMETER InputObject
        Pre-enumerated Graph objects to evaluate. Use DeleteUrl for nested resources
        whose delete URL cannot be derived from a flat endpoint.
    .PARAMETER KnownTemplateNames
        Case-insensitive HashSet of current template names used to scope deletes.
    .PARAMETER CandidateFilter
        Optional predicate for endpoints that contain multiple Graph resource types.
        The object is skipped when the predicate returns false.
    .OUTPUTS
        hashtable[] containing Name, Id, and Url for batch delete operations.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter()]
        [string[]]$Endpoint,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$InputObject = @(),

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [System.Collections.Generic.HashSet[string]]$KnownTemplateNames,

        [Parameter()]
        [scriptblock]$CandidateFilter
    )

    $deleteCandidates = @()

    function Add-HydrationDeleteCandidate {
        param(
            [Parameter(Mandatory)]
            [object]$GraphObject,

            [Parameter()]
            [string]$EndpointPath
        )

        $objectName = if ($GraphObject.displayName) {
            $GraphObject.displayName
        } elseif ($GraphObject.name) {
            $GraphObject.name
        } elseif ($GraphObject.Name) {
            $GraphObject.Name
        } else {
            'Unknown'
        }

        if ($CandidateFilter -and -not [bool](& $CandidateFilter $GraphObject)) {
            Write-Verbose "Skipping '$objectName' - object type is not in scope for this delete operation"
            return $null
        }

        $fullObjectUri = if ($GraphObject.FullObjectUri) {
            $GraphObject.FullObjectUri
        } elseif ($EndpointPath) {
            "$EndpointPath/$($GraphObject.id)"
        } else {
            $null
        }

        $deleteDecision = Resolve-HydrationMarkedDeleteCandidate `
            -Name $objectName `
            -Description $GraphObject.description `
            -Notes $GraphObject.notes `
            -KnownTemplateNames $KnownTemplateNames `
            -FullObjectUri $fullObjectUri

        if (-not $deleteDecision.IsMatch) {
            Write-Verbose "Skipping '$objectName' - $($deleteDecision.Message)"
            return $null
        }

        $deleteUrl = if ($GraphObject.DeleteUrl) {
            $GraphObject.DeleteUrl
        } elseif ($EndpointPath) {
            "/$($EndpointPath -replace '^beta/', '')/$($GraphObject.id)"
        } else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($deleteUrl)) {
            Write-Warning "Skipping '$objectName' - no delete URL could be resolved"
            return $null
        }

        return @{
            Name = $objectName
            Id   = $GraphObject.id
            Url  = $deleteUrl
        }
    }

    foreach ($candidateObject in $InputObject) {
        $candidate = Add-HydrationDeleteCandidate -GraphObject $candidateObject
        if ($candidate) {
            $deleteCandidates += $candidate
        }
    }

    foreach ($currentEndpoint in $Endpoint) {
        # Endpoints may carry a $filter query for listing; strip it for per-object URIs
        $endpointPath = ($currentEndpoint -split '\?', 2)[0]
        try {
            $allPolicies = Get-GraphPagedResults -Uri $currentEndpoint
            foreach ($policy in $allPolicies) {
                $candidate = Add-HydrationDeleteCandidate -GraphObject $policy -EndpointPath $endpointPath
                if ($candidate) {
                    $deleteCandidates += $candidate
                }
            }
        } catch {
            Write-Warning "Failed to list policies from $currentEndpoint : $_"
        }
    }

    return $deleteCandidates
}
