function Import-HydrationDevicePreparationPolicy {
    <#
    .SYNOPSIS
        Creates a Windows Autopilot Device Preparation policy from a template.
    .DESCRIPTION
        Skips creation when any policy with a matching prefixed or legacy name
        exists. Assigns the device preparation group to the User Driven policy.
    .PARAMETER Template
        Parsed enrollment template object.
    .PARAMETER ProfileName
        Prefixed policy name.
    .PARAMETER TemplateBaseName
        Legacy unprefixed template name.
    .OUTPUTS
        Hydration result objects.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template,

        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter()]
        [string]$TemplateBaseName
    )

    try {
        # Check if policy exists - filter by technologies (name filter not supported)
        $existingPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/configurationPolicies?`$filter=technologies eq 'enrollment'" -ErrorAction Stop

        $existingMatch = Select-HydrationExistingMatch -Candidates $existingPolicies.value -Name $ProfileName -LegacyName $TemplateBaseName -NameProperty 'name' -PreferTagged
        $existingPolicyId = $existingMatch.id

        if ($existingPolicyId) {
            # Verify the policy still exists (handles eventual consistency after deletes)
            if (-not (Test-GraphResourceExists -Uri "beta/deviceManagement/configurationPolicies/$existingPolicyId")) {
                Write-Verbose "Device preparation policy '$ProfileName' (ID: $existingPolicyId) no longer exists - proceeding to create"
                $existingPolicyId = $null
            }
        }

        if ($existingPolicyId) {
            Write-HydrationLog -Message "  Skipped: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'AutopilotDevicePreparation' -Id $existingPolicyId -Action 'Skipped' -Status 'Already exists'
        }

        if (-not $PSCmdlet.ShouldProcess($ProfileName, "Create Autopilot device preparation policy")) {
            Write-HydrationLog -Message "  WouldCreate: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'AutopilotDevicePreparation' -Action 'WouldCreate' -Status 'DryRun'
        }

        $policyDescription = New-HydrationDescription -ExistingText $Template.description

        $policyBody = @{
            name              = $ProfileName
            description       = $policyDescription
            platforms         = $Template.platforms
            technologies      = $Template.technologies
            templateReference = $Template.templateReference
            settings          = if ($Template.settings) { $Template.settings } else { @() }
        } | ConvertTo-Json -Depth 20

        $newPolicy = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/configurationPolicies" -Body $policyBody -ErrorAction Stop

        Write-HydrationLog -Message "  Created: $ProfileName" -Level Info

        # For "Windows Autopilot device preparation - User Driven", assign the device preparation group
        if ($ProfileName -eq "$($script:ImportPrefix)Windows Autopilot device preparation - User Driven") {
            try {
                $groupName = "$($script:ImportPrefix)Windows Autopilot device preparation"
                $safeGroupName = $groupName -replace "'", "''"
                $groupResponse = Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$safeGroupName'" -ErrorAction Stop
                $prepGroup = $groupResponse.value | Select-Object -First 1

                if ($prepGroup) {
                    # Set the enrollment time device membership target
                    $targetBody = @{
                        enrollmentTimeDeviceMembershipTargets = @(
                            @{
                                targetType = "staticSecurityGroup"
                                targetId   = $prepGroup.id
                            }
                        )
                    }
                    Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/configurationPolicies('$($newPolicy.id)')/setEnrollmentTimeDeviceMembershipTarget" -Body $targetBody -ErrorAction Stop
                    Write-HydrationLog -Message "    Assigned group: $groupName" -Level Info
                } else {
                    Write-HydrationLog -Message "    Warning: Group '$groupName' not found - skipping group assignment" -Level Warning
                }
            } catch {
                $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                Write-HydrationLog -Message "    Failed to assign group: $errMessage" -Level Warning
            }
        }

        return New-HydrationResult -Name $ProfileName -Type 'AutopilotDevicePreparation' -Id $newPolicy.id -Action 'Created' -Status 'Success'
    } catch {
        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
        Write-HydrationLog -Message "  Failed: $ProfileName - $errMessage" -Level Warning
        return New-HydrationResult -Name $ProfileName -Type 'AutopilotDevicePreparation' -Action 'Failed' -Status $errMessage
    }
}
