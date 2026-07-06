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
    .PARAMETER KnownNames
        Optional HashSet of known template display names (unprefixed). When provided during delete,
        only groups whose unprefixed name is in this set will be deleted (template-scoped delete).
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
        [switch]$Delete,

        [Parameter()]
        [System.Collections.Generic.HashSet[string]]$KnownNames
    )

    $results = @()
    $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }
    $maxRetries = 3
    $retryDelaySeconds = 2

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

        # Get all groups of this type, then filter locally.
        # Avoids ProcessItems scriptblock scope issue ($var += inside & {} creates a local copy).
        $groupsToDelete = @()
        $headers = @{ 'ConsistencyLevel' = 'eventual' }

        try {
            $allGroups = Get-GraphPagedResults -Uri "beta/groups?`$filter=$typeFilter&`$select=id,displayName,description&`$count=true" -Headers $headers
            foreach ($group in $allGroups) {
                $deleteDecision = Resolve-HydrationMarkedDeleteCandidate `
                    -Name $group.displayName `
                    -Description $group.description `
                    -KnownTemplateNames $KnownNames `
                    -FullObjectUri "beta/groups/$($group.id)"
                if (-not $deleteDecision.IsMatch) {
                    Write-Verbose "  Skipping '$($group.displayName)' - $($deleteDecision.Message)"
                    continue
                }

                $groupsToDelete += $group
            }
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

        $deleteItems = @()
        foreach ($group in $groupsToDelete) {
            $deleteItems += @{
                Name = $group.displayName
                Id   = $group.id
            }
        }

        $results += Invoke-GraphBatchOperation -Items $deleteItems -Operation 'DELETE' -BaseUrl '/groups' -ResultType $resultTypeName
        return $results
    }

    #endregion

    # Apply import prefix - create copies to avoid mutating caller's objects
    $importPrefix = if ([string]::IsNullOrEmpty($script:ImportPrefix)) { '[IHD] ' } else { $script:ImportPrefix }
    $prefixedDefinitions = @()
    foreach ($gd in $GroupDefinitions) {
        $copy = $gd | Select-Object *
        $originalName = $gd.displayName
        if ($copy.displayName -and -not [string]::IsNullOrEmpty($importPrefix) -and -not $copy.displayName.StartsWith($importPrefix)) {
            $copy.displayName = "$importPrefix$($copy.displayName)"
        }
        $copy | Add-Member -NotePropertyName '_OriginalDisplayName' -NotePropertyValue $originalName -Force
        $prefixedDefinitions += $copy
    }

    #region Phase 1: Batch Existence Checks

    Write-Verbose "Checking existence of $($prefixedDefinitions.Count) groups in batches..."

    $existingGroups = @{}  # displayName -> group object
    $groupsToCreate = @()

    # Build batch requests for existence checks
    for ($batchStart = 0; $batchStart -lt $prefixedDefinitions.Count; $batchStart += $maxBatchSize) {
        $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $prefixedDefinitions.Count) - 1
        $currentBatch = $prefixedDefinitions[$batchStart..$batchEnd]

        $batchEntries = @()
        for ($i = 0; $i -lt $currentBatch.Count; $i++) {
            $groupDef = $currentBatch[$i]
            $request = @{
                id     = ($i + 1).ToString()
                method = "GET"
                url    = Get-HydrationGroupLookupUri -GroupDefinition $groupDef
            }
            $batchEntries += [pscustomobject]@{
                Id      = [string]$request.id
                Request = $request
                Item    = $groupDef
                Index   = $i
            }
        }

        # Submit batch request
        $batchBody = @{ requests = @($batchEntries | ForEach-Object { $_.Request }) }
        try {
            $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop
            $responseState = Resolve-HydrationBatchResponse -BatchEntries $batchEntries -Responses @(Get-HydrationGroupBatchResponses -BatchResponse $batchResponse)
            $results += New-HydrationBatchCorrelationFailure -ResponseState $responseState -ResultTypeName $resultTypeName -StatusPrefix 'Existence check'

            # Process responses
            foreach ($resolvedResponse in $responseState.Matched) {
                $resp = $resolvedResponse.Response
                $groupDef = $resolvedResponse.Item

                if ($resp.status -eq 200 -and $resp.body.value.Count -gt 0) {
                    # Group exists - prefer the prefixed name match when multiple results
                    $existingGroups[$groupDef.displayName] = Select-HydrationGroupLookupMatch -LookupResult $resp.body -GroupDefinition $groupDef
                } elseif ($resp.status -eq 200) {
                    # Group does not exist - add to creation list
                    $groupsToCreate += $groupDef
                } else {
                    # Error checking existence - log and skip
                    Write-Warning "Failed to check existence of '$($groupDef.displayName)': HTTP $($resp.status)"
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Existence check failed: HTTP $($resp.status)"
                }
            }

            foreach ($missingRequest in $responseState.Missing) {
                $missingResolution = Resolve-HydrationMissingGroupExistence -MissingRequest $missingRequest -ResultTypeName $resultTypeName
                if ($missingResolution.ExistingGroup) {
                    $existingGroups[$missingRequest.Item.displayName] = $missingResolution.ExistingGroup
                } elseif ($missingResolution.GroupToCreate) {
                    $groupsToCreate += $missingResolution.GroupToCreate
                }
                if ($missingResolution.Result) {
                    $results += $missingResolution.Result
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

        $pendingGroups = @($currentBatch)
        $retryCount = 0

        while ($pendingGroups.Count -gt 0 -and $retryCount -le $maxRetries) {
            if ($retryCount -gt 0) {
                $maxRetryAfter = 0
                foreach ($groupDef in $pendingGroups) {
                    if ($groupDef.RetryAfter) {
                        $parsedRetryAfter = 0
                        if ([int]::TryParse([string]$groupDef.RetryAfter, [ref]$parsedRetryAfter) -and $parsedRetryAfter -gt $maxRetryAfter) {
                            $maxRetryAfter = $parsedRetryAfter
                        }
                        $groupDef.PSObject.Properties.Remove('RetryAfter')
                    }
                }
                $delay = if ($maxRetryAfter -gt 0) { $maxRetryAfter } else { $retryDelaySeconds * [Math]::Pow(2, $retryCount - 1) }
                Start-Sleep -Seconds $delay
            }

            $batchEntries = @()
            for ($i = 0; $i -lt $pendingGroups.Count; $i++) {
                $groupDef = $pendingGroups[$i]
                $request = @{
                    id      = ($i + 1).ToString()
                    method  = "POST"
                    url     = "/groups"
                    headers = @{ "Content-Type" = "application/json" }
                    body    = ConvertTo-HydrationGroupBody -GroupDefinition $groupDef -GroupType $GroupType
                }
                $batchEntries += [pscustomobject]@{
                    Id      = [string]$request.id
                    Request = $request
                    Item    = $groupDef
                    Index   = $i
                }
            }

            $itemsToRetry = @()
            $batchBody = @{ requests = @($batchEntries | ForEach-Object { $_.Request }) }
            try {
                $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop
            } catch {
                $statusCode = Get-GraphStatusCode -ErrorRecord $_
                if ($statusCode -eq 429) {
                    if ($retryCount -lt $maxRetries) {
                        $itemsToRetry = $pendingGroups
                    } else {
                        foreach ($groupDef in $pendingGroups) {
                            $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Creation failed: batch request throttled after retries: $_"
                        }
                    }
                    $pendingGroups = $itemsToRetry
                    $retryCount++
                    continue
                }

                $reason = "Batch creation request failed before responses: $_"
                Write-Warning $reason
                foreach ($groupDef in $pendingGroups) {
                    $results += Resolve-HydrationIndeterminateGroupCreate -GroupDefinition $groupDef -ResultTypeName $resultTypeName -Reason $reason
                }
                break
            }

            $responseState = Resolve-HydrationBatchResponse -BatchEntries $batchEntries -Responses @(Get-HydrationGroupBatchResponses -BatchResponse $batchResponse)
            $results += New-HydrationBatchCorrelationFailure -ResponseState $responseState -ResultTypeName $resultTypeName -StatusPrefix 'Creation'

            # Process responses
            foreach ($resolvedResponse in $responseState.Matched) {
                $resp = $resolvedResponse.Response
                $groupDef = $resolvedResponse.Item

                if ($resp.status -eq 201) {
                    # Created successfully
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Id $resp.body.id -Action 'Created' -Status 'New group created'
                    Write-Verbose "  Created: $($groupDef.displayName)"
                } elseif ($resp.status -eq 409) {
                    # Conflict - group was created between existence check and creation (race condition)
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Skipped' -Status 'Group already exists (race condition)'
                    Write-Verbose "  Skipped: $($groupDef.displayName) (race condition)"
                } elseif ((Test-HydrationBatchStatusRetryable -Status $resp.status -Operation 'POST') -and $retryCount -lt $maxRetries) {
                    $retryAfterSeconds = Get-HydrationBatchRetryAfterSeconds -Headers $resp.headers -Body $resp.body
                    if ($retryAfterSeconds) {
                        $groupDef | Add-Member -NotePropertyName RetryAfter -NotePropertyValue $retryAfterSeconds -Force
                    }
                    $itemsToRetry += $groupDef
                } elseif ($resp.status -ge 500 -and $resp.status -lt 600) {
                    $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                    $results += Resolve-HydrationIndeterminateGroupCreate -GroupDefinition $groupDef -ResultTypeName $resultTypeName -Reason "Batch creation returned $errorMessage"
                } else {
                    # Creation failed
                    $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                    $results += New-HydrationResult -Type $resultTypeName -Name $groupDef.displayName -Action 'Failed' -Status "Creation failed: $errorMessage"
                    Write-Warning "  Failed: $($groupDef.displayName) - $errorMessage"
                }
            }

            foreach ($missingRequest in $responseState.Missing) {
                $results += Resolve-HydrationIndeterminateGroupCreate -GroupDefinition $missingRequest.Item -ResultTypeName $resultTypeName -Reason 'No response received from Graph API'
            }

            $pendingGroups = $itemsToRetry
            $retryCount++
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
        $graphBaseUri = (Get-HydrationGraphEnvironmentInfo -Environment $mgContext.Environment).Endpoint

        # Create each SP owner group sequentially (need to add owner after creation)
        foreach ($groupDef in $spOwnerGroups) {
            try {
                $groupBody = ConvertTo-HydrationGroupBody -GroupDefinition $groupDef -GroupType 'Static'
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
