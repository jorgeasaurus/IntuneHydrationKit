function New-IntuneStaticGroup {
    <#
    .SYNOPSIS
        Creates a static Azure AD security group for Intune
    .DESCRIPTION
        Creates a static (assigned) security group. If a group with the same name exists, returns the existing group.
        For Autopilot device preparation groups, adds the Intune Provisioning Client as owner.
    .PARAMETER DisplayName
        The display name for the group
    .PARAMETER Description
        Description of the group
    .PARAMETER RequiresServicePrincipalOwner
        If set, adds the Intune Provisioning Client service principal as owner (required for Autopilot device preparation)
    .EXAMPLE
        New-IntuneStaticGroup -DisplayName "Intune - Update Ring Pilot Users" -Description "Users for pilot ring"
    .EXAMPLE
        New-IntuneStaticGroup -DisplayName "Windows Autopilot device preparation" -RequiresServicePrincipalOwner
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [switch]$RequiresServicePrincipalOwner
    )

    # Intune Provisioning Client app ID (required for Autopilot device preparation)
    $intuneProvisioningClientAppId = "f1346770-5b25-470b-88bd-d5744ab7952c"

    try {
        # If this group requires the service principal owner, ensure it exists first
        $servicePrincipalId = $null
        if ($RequiresServicePrincipalOwner) {
            Write-Verbose "Checking for Intune Provisioning Client service principal..."
            try {
                $spResponse = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '$intuneProvisioningClientAppId'" -ErrorAction Stop
                $existingSP = $spResponse.value | Select-Object -First 1

                if ($existingSP) {
                    $servicePrincipalId = $existingSP.id
                    Write-Verbose "Found existing service principal: $servicePrincipalId"
                } else {
                    # Create the service principal
                    Write-Verbose "Service principal not found, creating..."
                    if ($PSCmdlet.ShouldProcess("Intune Provisioning Client", "Create service principal")) {
                        $newSP = Invoke-MgGraphRequest -Method POST -Uri "v1.0/servicePrincipals" -Body @{ appId = $intuneProvisioningClientAppId } -ErrorAction Stop
                        $servicePrincipalId = $newSP.id
                        Write-Verbose "Created service principal: $servicePrincipalId"
                    }
                }
            } catch {
                $spError = $_.Exception.Message
                Write-HydrationLog -Message "  Warning: Could not get/create service principal: $spError" -Level Warning
                # Continue without the service principal - group can still be created
            }
        }

        # Check if group already exists (escape single quotes for OData filter)
        $safeDisplayName = $DisplayName -replace "'", "''"
        $listUri = "v1.0/groups?`$filter=displayName eq '$safeDisplayName'"
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
            # If service principal owner is required, ensure it's an owner
            if ($RequiresServicePrincipalOwner -and $servicePrincipalId) {
                if ($PSCmdlet.ShouldProcess($DisplayName, "Ensure Intune Provisioning Client is owner")) {
                    try {
                        $ownerRef = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId" }
                        Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($existingGroup.id)/owners/`$ref" -Body $ownerRef -ErrorAction Stop
                        return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Type 'StaticGroup' -Action 'Updated' -Status 'Added service principal owner'
                    } catch {
                        # Check if the error is "already exists" - that's fine, means SP is already owner
                        $errorMsg = $_.Exception.Message
                        if ($_.ErrorDetails.Message) {
                            $errorMsg = $_.ErrorDetails.Message
                        }
                        if ($errorMsg -like "*already exist*") {
                            Write-Verbose "Service principal is already an owner of $DisplayName"
                            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Type 'StaticGroup' -Action 'Skipped' -Status 'Group already exists with correct owner'
                        }
                        # Re-throw other errors
                        throw
                    }
                }
            }
            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Type 'StaticGroup' -Action 'Skipped' -Status 'Group already exists'
        }

        # Create new static group
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create static group")) {
            $fullDescription = if ($Description) { "$Description - Imported by Intune Hydration Kit" } else { "Imported by Intune Hydration Kit" }

            # Generate a safe mailNickname (alphanumeric only, max 64 chars)
            $mailNickname = ($DisplayName -replace '[^a-zA-Z0-9]', '')
            if ($mailNickname.Length -gt 64) {
                $mailNickname = $mailNickname.Substring(0, 64)
            }
            # Ensure mailNickname is not empty
            if ([string]::IsNullOrWhiteSpace($mailNickname)) {
                $mailNickname = "group" + [guid]::NewGuid().ToString("N").Substring(0, 8)
            }

            $groupBody = @{
                displayName     = $DisplayName
                description     = $fullDescription
                mailEnabled     = $false
                mailNickname    = $mailNickname
                securityEnabled = $true
            }

            Write-Verbose "Creating group with body: $($groupBody | ConvertTo-Json -Compress)"
            $newGroup = Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups" -Body $groupBody -ErrorAction Stop

            # Add service principal as owner if required
            if ($RequiresServicePrincipalOwner -and $servicePrincipalId) {
                $ownerRef = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId" }
                Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($newGroup.id)/owners/`$ref" -Body $ownerRef -ErrorAction Stop
                return New-HydrationResult -Name $newGroup.displayName -Id $newGroup.id -Type 'StaticGroup' -Action 'Created' -Status 'Created with service principal owner'
            }

            return New-HydrationResult -Name $newGroup.displayName -Id $newGroup.id -Type 'StaticGroup' -Action 'Created' -Status 'New group created'
        } else {
            return New-HydrationResult -Name $DisplayName -Type 'StaticGroup' -Action 'WouldCreate' -Status 'DryRun'
        }
    } catch {
        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
        Write-HydrationLog -Message "  Failed: $DisplayName - $errMessage" -Level Warning
        return New-HydrationResult -Name $DisplayName -Type 'StaticGroup' -Action 'Failed' -Status $errMessage
    }
}
