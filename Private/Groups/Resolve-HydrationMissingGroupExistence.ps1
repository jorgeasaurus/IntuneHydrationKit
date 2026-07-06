function Resolve-HydrationMissingGroupExistence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MissingRequest,

        [Parameter(Mandatory)]
        [string]$ResultTypeName
    )

    $groupDef = $MissingRequest.Item
    Write-Warning "Missing batch existence response for '$($groupDef.displayName)' - retrying directly"

    try {
        $lookupResult = Invoke-MgGraphRequest -Method GET -Uri "beta$($MissingRequest.Request.url)" -ErrorAction Stop
        $matchingGroup = Select-HydrationGroupLookupMatch -LookupResult $lookupResult -GroupDefinition $groupDef
        return [pscustomobject]@{
            ExistingGroup = $matchingGroup
            GroupToCreate = if ($matchingGroup) { $null } else { $groupDef }
            Result        = $null
        }
    } catch {
        $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
        Write-Warning "  Failed to check existence of '$($groupDef.displayName)': $errorMessage"
        return [pscustomobject]@{
            ExistingGroup = $null
            GroupToCreate = $null
            Result        = New-HydrationResult -Type $ResultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Existence check failed: $errorMessage"
        }
    }
}
