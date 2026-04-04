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
        # Compute final display name with prefix for both lookup and creation
        $finalDisplayName = "$($script:ImportPrefix)$DisplayName"
        $safeFinalName = $finalDisplayName -replace "'", "''"
        $safeOrigName = $DisplayName -replace "'", "''"

        # Check for both prefixed and unprefixed names (backward compat with pre-prefix groups)
        $allMatches = Get-GraphPagedResults -Uri "beta/groups?`$select=id,displayName,description&`$filter=displayName eq '$safeFinalName' or displayName eq '$safeOrigName'"

        # Prefer prefixed+tagged match, then any tagged match, then exact prefixed name (to avoid duplicates)
        $existingGroup = $null
        if ($allMatches) {
            foreach ($match in $allMatches) {
                $isTagged = Test-HydrationKitObject -Description $match.description -ObjectName $match.displayName
                if ($match.displayName -eq $finalDisplayName -and $isTagged) {
                    $existingGroup = $match
                    break
                }
                if ($isTagged -and -not $existingGroup) {
                    $existingGroup = $match
                }
            }
            # Fallback: if no tagged match, still skip exact prefixed name to avoid duplicates
            if (-not $existingGroup) {
                $existingGroup = $allMatches | Where-Object { $_.displayName -eq $finalDisplayName } | Select-Object -First 1
            }
        }

        if ($existingGroup) {
            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Type 'DynamicGroup' -Action 'Skipped' -Status 'Group already exists'
        }

        # Create new dynamic group
        if ($PSCmdlet.ShouldProcess($finalDisplayName, "Create dynamic group")) {
            $fullDescription = New-HydrationDescription -ExistingText $Description
            $groupBody = @{
                displayName                   = $finalDisplayName
                description                   = $fullDescription
                mailEnabled                   = $false
                mailNickname                  = ($DisplayName -replace '[^a-zA-Z0-9]', '')
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
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Failed to create group '$DisplayName': $($_.Exception.Message)", $_.Exception),
            'GroupCreationFailed',
            [System.Management.Automation.ErrorCategory]::WriteError,
            $DisplayName
        )
        $PSCmdlet.WriteError($errorRecord)
        return New-HydrationResult -Name $DisplayName -Type 'DynamicGroup' -Action 'Failed' -Status $_.Exception.Message
    }
}