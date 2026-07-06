function Resolve-HydrationIndeterminateGroupCreate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$GroupDefinition,

        [Parameter(Mandatory)]
        [string]$ResultTypeName,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    Write-Warning "$Reason for '$($GroupDefinition.displayName)' - verifying directly"

    try {
        $lookupResult = Invoke-MgGraphRequest -Method GET -Uri "beta$(Get-HydrationGroupLookupUri -GroupDefinition $GroupDefinition)" -ErrorAction Stop
        $matchingGroup = Select-HydrationGroupLookupMatch -LookupResult $lookupResult -GroupDefinition $GroupDefinition -PreferHydrationMarker
        if ($matchingGroup) {
            Write-Verbose "  Verified: $($GroupDefinition.displayName) exists after indeterminate creation response"
            return New-HydrationResult -Type $ResultTypeName -Name $GroupDefinition.displayName -Id $matchingGroup.id -Action 'Skipped' -Status 'Group exists after indeterminate creation response'
        }

        $statusMessage = "Creation indeterminate: $Reason; not retried to avoid duplicate group creation"
        Write-Warning "  Failed: $($GroupDefinition.displayName) - $statusMessage"
        return New-HydrationResult -Type $ResultTypeName -Name $GroupDefinition.displayName -Action 'Failed' -Status $statusMessage
    } catch {
        $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
        Write-Warning "  Failed: $($GroupDefinition.displayName) - $errorMessage"
        return New-HydrationResult -Type $ResultTypeName -Name $GroupDefinition.displayName -Action 'Failed' -Status "Creation indeterminate: $Reason and verification failed: $errorMessage"
    }
}
