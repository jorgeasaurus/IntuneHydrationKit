function Get-HydrationDeleteCandidates {
    <#
    .SYNOPSIS
        Finds Graph objects that are safe delete candidates for hydration cleanup.
    .DESCRIPTION
        Enumerates objects from Graph list endpoints, keeps only objects created by the
        Intune Hydration Kit, and optionally restricts matches to known template names.
        If a list response omits description or notes, the function performs a targeted
        GET for likely matches so the hydration marker can still be verified safely.
    .PARAMETER Endpoint
        One or more beta Graph endpoints to enumerate.
    .PARAMETER KnownTemplateNames
        Optional case-insensitive HashSet of current template names used to scope deletes.
    .PARAMETER RequireTemplateMatch
        When specified, only returns hydration kit objects whose names match a current template.
    .OUTPUTS
        hashtable[] containing Name, Id, and Url for batch delete operations.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Endpoint,

        [Parameter()]
        [System.Collections.Generic.HashSet[string]]$KnownTemplateNames,

        [Parameter()]
        [switch]$RequireTemplateMatch
    )

    $deleteCandidates = @()
    $importPrefix = if ([string]::IsNullOrEmpty($script:ImportPrefix)) { '[IHD] ' } else { $script:ImportPrefix }
    $escapedPrefix = [regex]::Escape($importPrefix)

    foreach ($currentEndpoint in $Endpoint) {
        try {
            $allPolicies = Get-GraphPagedResults -Uri $currentEndpoint
            foreach ($policy in $allPolicies) {
                $policyName = if ($policy.displayName) {
                    $policy.displayName
                } elseif ($policy.name) {
                    $policy.name
                } else {
                    'Unknown'
                }

                $unprefixedName = $policyName -replace "^$escapedPrefix", ''
                $matchesTemplateName = $false
                if ($KnownTemplateNames) {
                    $matchesTemplateName = $KnownTemplateNames.Contains($policyName) -or $KnownTemplateNames.Contains($unprefixedName)
                }

                $isHydrationKitObject = Test-HydrationKitObject -Description $policy.description -Notes $policy.notes -ObjectName $policyName
                $shouldVerifyWithGet = -not $isHydrationKitObject -and
                [string]::IsNullOrWhiteSpace($policy.description) -and
                [string]::IsNullOrWhiteSpace($policy.notes) -and
                ($policyName -match "^$escapedPrefix" -or $matchesTemplateName)

                if ($shouldVerifyWithGet) {
                    try {
                        $fullPolicy = Invoke-MgGraphRequest -Method GET -Uri "$currentEndpoint/$($policy.id)" -ErrorAction Stop
                        $isHydrationKitObject = Test-HydrationKitObject -Description $fullPolicy.description -Notes $fullPolicy.notes -ObjectName $policyName
                    } catch {
                        Write-Verbose "Could not verify hydration marker for '$policyName' from $currentEndpoint/$($policy.id): $_"
                    }
                }

                if (-not $isHydrationKitObject) {
                    Write-Verbose "Skipping '$policyName' - not created by Intune Hydration Kit"
                    continue
                }

                if ($RequireTemplateMatch -and $KnownTemplateNames -and -not $matchesTemplateName) {
                    continue
                }

                if (-not $RequireTemplateMatch -and $KnownTemplateNames -and -not $matchesTemplateName) {
                    Write-Verbose "Policy '$policyName' not in current templates (may be from an older baseline version) - deleting based on hydration kit marker"
                }

                $deleteCandidates += @{
                    Name = $policyName
                    Id   = $policy.id
                    Url  = "/$($currentEndpoint -replace '^beta/', '')/$($policy.id)"
                }
            }
        } catch {
            Write-Warning "Failed to list policies from $currentEndpoint : $_"
        }
    }

    return $deleteCandidates
}
