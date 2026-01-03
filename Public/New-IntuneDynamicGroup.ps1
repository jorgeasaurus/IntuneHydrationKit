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
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ $_ -match '^\(' }, ErrorMessage = "MembershipRule must start with a parenthesis")]
        [string]$MembershipRule,

        [Parameter()]
        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState = 'On'
    )

    try {
        # Check if group already exists (escape single quotes for OData filter)
        # Use pagination to handle large result sets
        $safeDisplayName = $DisplayName -replace "'", "''"
        $listUri = "beta/groups?`$filter=displayName eq '$safeDisplayName'"
        $existingGroup = $null
        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            if ($response.value.Count -gt 0) {
                $existingGroup = $response.value[0]
                break
            }
            $listUri = $response.'@odata.nextLink'
        } while ($listUri)

        if ($existingGroup) {
            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Type 'DynamicGroup' -Action 'Skipped' -Status 'Group already exists'
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

            $newGroup = Invoke-MgGraphRequest -Method POST -Uri "beta/groups" -Body $groupBody -ErrorAction Stop

            return New-HydrationResult -Name $newGroup.displayName -Id $newGroup.id -Type 'DynamicGroup' -Action 'Created' -Status 'New group created'
        }
        else {
            return New-HydrationResult -Name $DisplayName -Type 'DynamicGroup' -Action 'WouldCreate' -Status 'DryRun'
        }
    }
    catch {
        Write-Error "Failed to create group '$DisplayName': $_"
        return New-HydrationResult -Name $DisplayName -Type 'DynamicGroup' -Action 'Failed' -Status $_.Exception.Message
    }
}