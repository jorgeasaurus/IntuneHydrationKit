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
        $incompatibleGroup = $null
        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($group in @($response.value)) {
                $isDynamicGroup = @($group.groupTypes) -contains 'DynamicMembership'
                if ($isDynamicGroup) {
                    $existingGroup = $group
                    break
                }
                if (-not $incompatibleGroup) {
                    $incompatibleGroup = $group
                }
            }
            if ($existingGroup) {
                break
            }
            $listUri = $response.'@odata.nextLink'
        } while ($listUri)

        if ($existingGroup) {
            if ($existingGroup.membershipRule -ne $MembershipRule) {
                $ruleWarning = "Dynamic group '$DisplayName' already exists, but its membership rule differs from the requested rule."
                Write-HydrationLog -Message "  Warning: $ruleWarning" -Level Warning
                Write-Warning $ruleWarning
            }
            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Type 'DynamicGroup' -Action 'Skipped' -Status 'Group already exists'
        }

        if ($incompatibleGroup) {
            $status = 'A non-dynamic group with this displayName already exists'
            Write-HydrationLog -Message "  Failed: $DisplayName - $status" -Level Warning
            Write-Warning $status
            return New-HydrationResult -Name $DisplayName -Id $incompatibleGroup.id -Type 'DynamicGroup' -Action 'Failed' -Status $status
        }

        # Create new dynamic group
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create dynamic group")) {
            $fullDescription = if ($Description) { "$Description - Imported by Intune Hydration Kit" } else { "Imported by Intune Hydration Kit" }
            $mailNickname = ($DisplayName -replace '[^a-zA-Z0-9]', '')
            if ($mailNickname.Length -gt 64) {
                $mailNickname = $mailNickname.Substring(0, 64)
            }
            if ([string]::IsNullOrWhiteSpace($mailNickname)) {
                $mailNickname = "group" + [guid]::NewGuid().ToString("N").Substring(0, 8)
            }

            $groupBody = @{
                displayName                   = $DisplayName
                description                   = $fullDescription
                mailEnabled                   = $false
                mailNickname                  = $mailNickname
                securityEnabled               = $true
                groupTypes                    = @('DynamicMembership')
                membershipRule                = $MembershipRule
                membershipRuleProcessingState = $MembershipRuleProcessingState
            }

            $newGroup = Invoke-MgGraphRequest -Method POST -Uri "beta/groups" -Body $groupBody -ErrorAction Stop

            return New-HydrationResult -Name $newGroup.displayName -Id $newGroup.id -Type 'DynamicGroup' -Action 'Created' -Status 'New group created'
        } else {
            return New-HydrationResult -Name $DisplayName -Type 'DynamicGroup' -Action 'WouldCreate' -Status 'DryRun'
        }
    } catch {
        Write-Error "Failed to create group '$DisplayName': $_"
        return New-HydrationResult -Name $DisplayName -Type 'DynamicGroup' -Action 'Failed' -Status $_.Exception.Message
    }
}