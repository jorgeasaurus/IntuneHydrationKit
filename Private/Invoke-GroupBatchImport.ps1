function Invoke-GroupBatchImport {
    <#
    .SYNOPSIS
        Batch imports or deletes groups using Graph API batch requests for improved performance
    .DESCRIPTION
        Creates or deletes dynamic or static groups using batched Graph API requests to reduce API calls.
        For creation: Batches existence checks (up to 20 per batch) and creation requests (up to 20 per batch).
        For deletion: Lists groups with hydration kit marker and batches DELETE requests.
        Returns results in standardized New-HydrationResult format.
    .PARAMETER GroupDefinitions
        Array of group definition objects from templates. Each must have displayName and description.
        Dynamic groups require membershipRule. Static groups may have requiresServicePrincipalOwner.
        Not required when using -Delete switch.
    .PARAMETER GroupType
        Type of groups to process: 'Dynamic' or 'Static'
    .PARAMETER Delete
        Switch to delete existing groups created by the hydration kit instead of creating new ones.
        Only groups with "Imported by Intune Hydration Kit" in their description will be deleted.
    .EXAMPLE
        Invoke-GroupBatchImport -GroupDefinitions $dynamicGroups -GroupType 'Dynamic'
    .EXAMPLE
        Invoke-GroupBatchImport -GroupDefinitions $staticGroups -GroupType 'Static' -WhatIf
    .EXAMPLE
        Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [array]$GroupDefinitions = @(),

        [ValidateSet('Dynamic', 'Static')]
        [string]$GroupType,

        [Parameter()]
        [switch]$Delete
    )

    # Helper function to build group request body from definition
    function ConvertTo-GroupBody {
        param(
            [Parameter(Mandatory)]
            [object]$GroupDef,
            [Parameter(Mandatory)]
            [string]$GroupType
        )

        $description = if ($GroupDef.description) {
            "$($GroupDef.description) - Imported by Intune Hydration Kit"
        } else {
            "Imported by Intune Hydration Kit"
        }

        # Generate safe mailNickname (alphanumeric only, max 64 chars)
        $mailNickname = ($GroupDef.displayName -replace '[^a-zA-Z0-9]', '')
        if ($mailNickname.Length -gt 64) {
            $mailNickname = $mailNickname.Substring(0, 64)
        }
        if ([string]::IsNullOrWhiteSpace($mailNickname)) {
            $mailNickname = "group" + [guid]::NewGuid().ToString("N").Substring(0, 8)
        }

        $body = @{
            displayName     = $GroupDef.displayName
            description     = $description
            mailEnabled     = $false
            mailNickname    = $mailNickname
            securityEnabled = $true
        }

        if ($GroupType -eq 'Dynamic') {
            $body['groupTypes'] = @('DynamicMembership')
            $body['membershipRule'] = $GroupDef.membershipRule
            $body['membershipRuleProcessingState'] = 'On'
        }

        return $body
    }

    # Helper function to get Graph base URI for the current environment
    function Get-GraphBaseUri {
        param([string]$Environment)
        switch ($Environment) {
            "USGov" { return "https://graph.microsoft.us" }
            "USGovDoD" { return "https://graph.microsoft.us" }
            "China" { return "https://graph.chinacloudapi.cn" }
            "Germany" { return "https://graph.microsoft.de" }
            default { return "https://graph.microsoft.com" }
        }
    }

    $results = @()
    $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }

    # Early return if no groups to process in create mode
    if (-not $Delete -and $GroupDefinitions.Count -eq 0) {
        return $results
    }

    # Verify Graph connection exists
    $mgContext = Get-MgContext
    if (-not $mgContext) {
        Write-Error "No Microsoft Graph connection found. Please connect using Connect-MgGraph."
        return $results
    }

    $resultTypeName = "${GroupType}Group"

    #region Delete Mode

    if ($Delete) {
        Write-Verbose "Delete mode: Finding $GroupType groups to delete..."

        # Build the filter based on group type
        $typeFilter = if ($GroupType -eq 'Dynamic') {
            "groupTypes/any(c:c eq 'DynamicMembership')"
        } else {
            "securityEnabled eq true and NOT groupTypes/any(c:c eq 'DynamicMembership')"
        }

        # Get all groups of this type
        $groupsToDelete = @()
        $listUri = "beta/groups?`$filter=$typeFilter&`$select=id,displayName,description&`$count=true"
        $headers = @{ 'ConsistencyLevel' = 'eventual' }

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $listUri -Headers $headers -ErrorAction Stop
                foreach ($group in $response.value) {
                    # Safety check: Only delete if created by this kit
                    if (Test-HydrationKitObject -Description $group.description -ObjectName $group.displayName) {
                        $groupsToDelete += $group
                    } else {
                        Write-Verbose "  Skipping '$($group.displayName)' - not created by Intune Hydration Kit"
                    }
                }
                $listUri = $response.'@odata.nextLink'
            } while ($listUri)
        } catch {
            Write-Warning "Failed to list $GroupType groups: $_"
            $results += New-HydrationResult -Type $resultTypeName -Name 'List operation' -Action 'Failed' -Status "Failed to list groups: $_"
            return $results
        }

        if ($groupsToDelete.Count -eq 0) {
            Write-Verbose "No $GroupType groups found to delete"
            return $results
        }

        Write-Verbose "Found $($groupsToDelete.Count) $GroupType groups to delete"

        # Handle WhatIf mode for deletion
        if ($WhatIfPreference) {
            foreach ($group in $groupsToDelete) {
                $results += New-HydrationResult -Type $resultTypeName -Name $group.displayName -Id $group.id -Action 'WouldDelete' -Status 'DryRun'
                Write-Verbose "  WouldDelete: $($group.displayName)"
            }
            return $results
        }

        # Batch delete groups
        for ($batchStart = 0; $batchStart -lt $groupsToDelete.Count; $batchStart += $maxBatchSize) {
            $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $groupsToDelete.Count) - 1
            $currentBatch = $groupsToDelete[$batchStart..$batchEnd]

            $batchRequests = @()
            for ($i = 0; $i -lt $currentBatch.Count; $i++) {
                $group = $currentBatch[$i]
                $batchRequests += @{
                    id     = ($i + 1).ToString()
                    method = "DELETE"
                    url    = "/groups/$($group.id)"
                }
            }

            # Submit batch delete request
            $batchBody = @{ requests = $batchRequests }
            try {
                $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop

                # Process responses
                foreach ($resp in $batchResponse.responses) {
                    $requestIndex = [int]$resp.id - 1
                    $group = $currentBatch[$requestIndex]

                    # Skip if we can't find the matching group
                    if (-not $group -or -not $group.displayName) {
                        Write-Verbose "Skipping response with id=$($resp.id) - no matching group"
                        continue
                    }

                    if ($resp.status -eq 204 -or $resp.status -eq 200) {
                        # Deleted successfully
                        $results += New-HydrationResult -Type $resultTypeName -Name $group.displayName -Id $group.id -Action 'Deleted' -Status 'Success'
                        Write-Verbose "  Deleted: $($group.displayName)"
                    } elseif ($resp.status -eq 404) {
                        # Already deleted (race condition)
                        $results += New-HydrationResult -Type $resultTypeName -Name $group.displayName -Action 'Skipped' -Status 'Already deleted'
                        Write-Verbose "  Skipped: $($group.displayName) (already deleted)"
                    } else {
                        # Deletion failed
                        $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                        $results += New-HydrationResult -Type $resultTypeName -Name $group.displayName -Id $group.id -Action 'Failed' -Status "Delete failed: $errorMessage"
                        Write-Warning "  Failed to delete: $($group.displayName) - $errorMessage"
                    }
                }
            } catch {
                # Batch request failed - log individual failures
                Write-Warning "Batch delete failed: $_"
                foreach ($group in $currentBatch) {
                    $results += New-HydrationResult -Type $resultTypeName -Name $group.displayName -Id $group.id -Action 'Failed' -Status "Batch delete failed: $_"
                }
            }
        }

        return $results
    }

    #endregion

    #region Phase 1: Batch Existence Checks

    Write-Verbose "Checking existence of $($GroupDefinitions.Count) groups in batches..."

    $existingGroups = @{}  # displayName -> group object
    $groupsToCreate = @()

    # Build batch requests for existence checks
    for ($batchStart = 0; $batchStart -lt $GroupDefinitions.Count; $batchStart += $maxBatchSize) {
        $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $GroupDefinitions.Count) - 1
        $currentBatch = $GroupDefinitions[$batchStart..$batchEnd]

        $batchRequests = @()
        for ($i = 0; $i -lt $currentBatch.Count; $i++) {
            $groupDef = $currentBatch[$i]
            # Escape single quotes for OData filter
            $safeDisplayName = $groupDef.displayName -replace "'", "''"
            $filterUri = "/groups?`$filter=displayName eq '$safeDisplayName'&`$select=id,displayName,description"

            $batchRequests += @{
                id     = ($i + 1).ToString()
                method = "GET"
                url    = $filterUri
            }
        }

        # Submit batch request
        $batchBody = @{ requests = $batchRequests }
        try {
            $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop

            # Process responses
            foreach ($resp in $batchResponse.responses) {
                $requestIndex = [int]$resp.id - 1
                $groupDef = $currentBatch[$requestIndex]

                # Skip if we can't find the matching group definition
                if (-not $groupDef -or -not $groupDef.displayName) {
                    Write-Verbose "Skipping response with id=$($resp.id) - no matching group definition"
                    continue
                }

                if ($resp.status -eq 200 -and $resp.body.value.Count -gt 0) {
                    # Group exists
                    $existingGroups[$groupDef.displayName] = $resp.body.value[0]
                } elseif ($resp.status -eq 200) {
                    # Group does not exist - add to creation list
                    $groupsToCreate += $groupDef
                } else {
                    # Error checking existence - log and skip
                    Write-Warning "Failed to check existence of '$($groupDef.displayName)': HTTP $($resp.status)"
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Existence check failed: HTTP $($resp.status)"
                }
            }
        } catch {
            # Batch request failed - fall back to individual results
            Write-Warning "Batch existence check failed: $_"
            foreach ($groupDef in $currentBatch) {
                $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Batch check failed: $_"
            }
        }
    }

    # Add skipped results for existing groups
    foreach ($displayName in $existingGroups.Keys) {
        $existingGroup = $existingGroups[$displayName]
        $results += New-HydrationResult -Type $resultTypeName -Name $displayName -Id $existingGroup.id -Action 'Skipped' -Status 'Group already exists'
        Write-Verbose "  Skipped: $displayName (already exists)"
    }

    #endregion

    #region Phase 2: Batch Creation

    if ($groupsToCreate.Count -eq 0) {
        Write-Verbose "No groups to create - all exist"
        return $results
    }

    Write-Verbose "Creating $($groupsToCreate.Count) groups in batches..."

    # Handle WhatIf mode
    if ($WhatIfPreference) {
        foreach ($groupDef in $groupsToCreate) {
            $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'WouldCreate' -Status 'DryRun'
            Write-Verbose "  WouldCreate: $($groupDef.displayName)"
        }
        return $results
    }

    # Separate groups that require service principal owner (static only)
    $spOwnerGroups = @()
    $regularGroups = @()

    foreach ($groupDef in $groupsToCreate) {
        if ($GroupType -eq 'Static' -and $groupDef.requiresServicePrincipalOwner) {
            $spOwnerGroups += $groupDef
        } else {
            $regularGroups += $groupDef
        }
    }

    # Create regular groups in batches
    for ($batchStart = 0; $batchStart -lt $regularGroups.Count; $batchStart += $maxBatchSize) {
        $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $regularGroups.Count) - 1
        $currentBatch = $regularGroups[$batchStart..$batchEnd]

        $batchRequests = @()
        for ($i = 0; $i -lt $currentBatch.Count; $i++) {
            $groupDef = $currentBatch[$i]
            $batchRequests += @{
                id      = ($i + 1).ToString()
                method  = "POST"
                url     = "/groups"
                headers = @{ "Content-Type" = "application/json" }
                body    = ConvertTo-GroupBody -GroupDef $groupDef -GroupType $GroupType
            }
        }

        # Submit batch creation request
        $batchBody = @{ requests = $batchRequests }
        try {
            $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop

            # Process responses
            foreach ($resp in $batchResponse.responses) {
                $requestIndex = [int]$resp.id - 1
                $groupDef = $currentBatch[$requestIndex]

                # Skip if we can't find the matching group definition
                if (-not $groupDef -or -not $groupDef.displayName) {
                    Write-Verbose "Skipping response with id=$($resp.id) - no matching group definition"
                    continue
                }

                if ($resp.status -eq 201) {
                    # Created successfully
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Id $resp.body.id -Action 'Created' -Status 'New group created'
                    Write-Verbose "  Created: $($groupDef.displayName)"
                } elseif ($resp.status -eq 409) {
                    # Conflict - group was created between existence check and creation (race condition)
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Skipped' -Status 'Group already exists (race condition)'
                    Write-Verbose "  Skipped: $($groupDef.displayName) (race condition)"
                } else {
                    # Creation failed
                    $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Creation failed: $errorMessage"
                    Write-Warning "  Failed: $($groupDef.displayName) - $errorMessage"
                }
            }
        } catch {
            # Batch request failed - log individual failures
            Write-Warning "Batch creation failed: $_"
            foreach ($groupDef in $currentBatch) {
                $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Batch creation failed: $_"
            }
        }
    }

    #endregion

    #region Phase 3: Service Principal Owner Groups (Sequential)

    if ($spOwnerGroups.Count -gt 0) {
        Write-Verbose "Creating $($spOwnerGroups.Count) groups that require service principal owner..."

        # Get or create the Intune Provisioning Client service principal
        $intuneProvisioningClientAppId = "f1346770-5b25-470b-88bd-d5744ab7952c"
        $servicePrincipalId = $null

        try {
            $spResponse = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '$intuneProvisioningClientAppId'" -ErrorAction Stop
            $existingSP = $spResponse.value | Select-Object -First 1

            if ($existingSP) {
                $servicePrincipalId = $existingSP.id
                Write-Verbose "Found existing Intune Provisioning Client service principal: $servicePrincipalId"
            } else {
                # Create the service principal
                Write-Verbose "Creating Intune Provisioning Client service principal..."
                $newSP = Invoke-MgGraphRequest -Method POST -Uri "v1.0/servicePrincipals" -Body @{ appId = $intuneProvisioningClientAppId } -ErrorAction Stop
                $servicePrincipalId = $newSP.id
                Write-Verbose "Created service principal: $servicePrincipalId"
            }
        } catch {
            Write-Warning "Could not get/create Intune Provisioning Client service principal: $_"
            # Continue without SP - groups can still be created but won't have the owner
        }

        # Get Graph base URI for owner reference
        $graphBaseUri = Get-GraphBaseUri -Environment $mgContext.Environment

        # Create each SP owner group sequentially (need to add owner after creation)
        foreach ($groupDef in $spOwnerGroups) {
            try {
                $groupBody = ConvertTo-GroupBody -GroupDef $groupDef -GroupType 'Static'
                $newGroup = Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups" -Body $groupBody -ErrorAction Stop

                # Add service principal as owner if available
                if ($servicePrincipalId) {
                    $ownerRef = @{ "@odata.id" = "$graphBaseUri/v1.0/servicePrincipals/$servicePrincipalId" }
                    Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($newGroup.id)/owners/`$ref" -Body $ownerRef -ErrorAction Stop
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Id $newGroup.id -Action 'Created' -Status 'Created with service principal owner'
                    Write-Verbose "  Created: $($groupDef.displayName) (with SP owner)"
                } else {
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Id $newGroup.id -Action 'Created' -Status 'Created (SP owner not available)'
                    Write-Verbose "  Created: $($groupDef.displayName) (SP owner unavailable)"
                }
            } catch {
                $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
                $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status $errorMessage
                Write-Warning "  Failed: $($groupDef.displayName) - $errorMessage"
            }
        }
    }

    #endregion

    return $results
}
