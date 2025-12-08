function New-IntuneStaticGroup {
    <#
    .SYNOPSIS
        Creates a static Azure AD security group for Intune
    .DESCRIPTION
        Creates a static (assigned) security group. If a group with the same name exists, returns the existing group.
    .PARAMETER DisplayName
        The display name for the group
    .PARAMETER Description
        Description of the group
    .EXAMPLE
        New-IntuneStaticGroup -DisplayName "Intune - Update Ring Pilot Users" -Description "Users for pilot ring"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter()]
        [string]$Description = ""
    )

    try {
        # Check if group already exists (escape single quotes for OData filter)
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
            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Type 'StaticGroup' -Action 'Skipped' -Status 'Group already exists'
        }

        # Create new static group
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create static group")) {
            $fullDescription = if ($Description) { "$Description - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }
            $groupBody = @{
                displayName     = $DisplayName
                description     = $fullDescription
                mailEnabled     = $false
                mailNickname    = ($DisplayName -replace '[^a-zA-Z0-9]', '')
                securityEnabled = $true
            }

            $newGroup = Invoke-MgGraphRequest -Method POST -Uri "beta/groups" -Body $groupBody -ErrorAction Stop

            return New-HydrationResult -Name $newGroup.displayName -Id $newGroup.id -Type 'StaticGroup' -Action 'Created' -Status 'New group created'
        }
        else {
            return New-HydrationResult -Name $DisplayName -Type 'StaticGroup' -Action 'WouldCreate' -Status 'DryRun'
        }
    }
    catch {
        Write-Error "Failed to create group '$DisplayName': $_"
        return New-HydrationResult -Name $DisplayName -Type 'StaticGroup' -Action 'Failed' -Status $_.Exception.Message
    }
}
