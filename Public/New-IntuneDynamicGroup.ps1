function New-IntuneDynamicGroup {
    <#
    .SYNOPSIS
        Creates a dynamic Azure AD group for Intune
    .DESCRIPTION
        Creates a dynamic group with the specified membership rule. If a group with the same name exists, returns the existing group.
    .PARAMETER DisplayName
        The display name for the group
    .PARAMETER Description
        Description of the group
    .PARAMETER MembershipRule
        OData membership rule for dynamic membership
    .PARAMETER MembershipRuleProcessingState
        Processing state for the rule (On or Paused)
    .EXAMPLE
        New-IntuneDynamicGroup -DisplayName "Windows 11 Devices" -MembershipRule "(device.operatingSystem -eq 'Windows') and (device.operatingSystemVersion -startsWith '10.0.22')"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter()]
        [string]$Description = "",

        [Parameter(Mandatory = $true)]
        [string]$MembershipRule,

        [Parameter()]
        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState = 'On'
    )

    try {
        # Check if group already exists
        $existingGroups = Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$DisplayName'" -ErrorAction Stop

        if ($existingGroups.value.Count -gt 0) {
            $existingGroup = $existingGroups.value[0]
            Write-Information "Group already exists: $DisplayName (ID: $($existingGroup.id))" -InformationAction Continue
            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Action 'Skipped' -Status 'Group already exists'
        }

        # Create new dynamic group
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create dynamic group")) {
            $fullDescription = if ($Description) { "$Description - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }
            $groupBody = @{
                displayName = $DisplayName
                description = $fullDescription
                mailEnabled = $false
                mailNickname = ($DisplayName -replace '[^a-zA-Z0-9]', '')
                securityEnabled = $true
                groupTypes = @('DynamicMembership')
                membershipRule = $MembershipRule
                membershipRuleProcessingState = $MembershipRuleProcessingState
            }

            $newGroup = Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups" -Body $groupBody -ErrorAction Stop

            Write-Information "Created group: $DisplayName (ID: $($newGroup.id))" -InformationAction Continue

            return New-HydrationResult -Name $newGroup.displayName -Id $newGroup.id -Action 'Created' -Status 'New group created'
        }
        else {
            return New-HydrationResult -Name $DisplayName -Action 'Skipped' -Status 'WhatIf mode'
        }
    }
    catch {
        Write-Error "Failed to create group '$DisplayName': $_"
        return New-HydrationResult -Name $DisplayName -Action 'Failed' -Status $_.Exception.Message
    }
}