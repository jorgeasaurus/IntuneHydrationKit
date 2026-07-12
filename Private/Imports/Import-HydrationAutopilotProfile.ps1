function Import-HydrationAutopilotProfile {
    <#
    .SYNOPSIS
        Creates a Windows Autopilot deployment profile from a template.
    .DESCRIPTION
        Skips creation when any profile with a matching prefixed or legacy name
        exists. Retries with safe defaults when the tenant lacks licensing for
        pre-provisioning or hardware hash extraction.
    .PARAMETER Template
        Parsed enrollment template object.
    .PARAMETER ProfileName
        Prefixed profile display name.
    .PARAMETER TemplateBaseName
        Legacy unprefixed template name.
    .PARAMETER DeviceNameTemplate
        Optional device naming template override.
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
        [string]$TemplateBaseName,

        [Parameter()]
        [string]$DeviceNameTemplate
    )

    try {
        # Check if profile exists - check both prefixed and unprefixed names (backward compat with pre-prefix profiles)
        $safeProfileName = $ProfileName -replace "'", "''"
        $filter = "displayName eq '$safeProfileName'"
        if (-not [string]::IsNullOrWhiteSpace($TemplateBaseName) -and $TemplateBaseName -ne $ProfileName) {
            $safeOriginalName = $TemplateBaseName -replace "'", "''"
            $filter += " or displayName eq '$safeOriginalName'"
        }
        $existingProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=$filter" -ErrorAction Stop

        $existingMatch = Select-HydrationExistingMatch -Candidates $existingProfiles.value -Name $ProfileName -LegacyName $TemplateBaseName -PreferTagged
        $existingProfileId = $existingMatch.id

        if ($existingProfileId) {
            # Verify the profile still exists (handles eventual consistency after deletes)
            if (-not (Test-GraphResourceExists -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles/$existingProfileId")) {
                Write-Verbose "Autopilot profile '$ProfileName' (ID: $existingProfileId) no longer exists - proceeding to create"
                $existingProfileId = $null
            }
        }

        if ($existingProfileId) {
            Write-HydrationLog -Message "  Skipped: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'AutopilotDeploymentProfile' -Id $existingProfileId -Action 'Skipped' -Status 'Already exists'
        }

        if (-not $PSCmdlet.ShouldProcess($ProfileName, "Create Autopilot deployment profile")) {
            Write-HydrationLog -Message "  WouldCreate: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'AutopilotDeploymentProfile' -Action 'WouldCreate' -Status 'DryRun'
        }

        # Autopilot deployment profiles reject the ' - ' separator in descriptions;
        # use a space-only separator so no dash is introduced by the hydration tag.
        $profileDescription = New-HydrationDescription -ExistingText $Template.description -Separator ' '

        # Apply custom device name template if provided
        $deviceName = if ($DeviceNameTemplate) { $DeviceNameTemplate } else { $Template.deviceNameTemplate }

        # Build profile body matching the exact format the Graph API accepts
        # (verified against Intune console's working POST payload)
        $profileBody = @{
            "@odata.type"                          = "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile"
            displayName                            = $ProfileName
            description                            = $profileDescription
            deviceNameTemplate                     = $deviceName
            locale                                 = $Template.locale
            preprovisioningAllowed                 = [bool]$Template.preprovisioningAllowed
            deviceType                             = $Template.deviceType
            hardwareHashExtractionEnabled          = [bool]$Template.hardwareHashExtractionEnabled
            roleScopeTagIds                        = @()
            hybridAzureADJoinSkipConnectivityCheck = [bool]$Template.hybridAzureADJoinSkipConnectivityCheck
            outOfBoxExperienceSetting              = @{
                deviceUsageType              = $Template.outOfBoxExperienceSetting.deviceUsageType
                escapeLinkHidden             = [bool]$Template.outOfBoxExperienceSetting.escapeLinkHidden
                privacySettingsHidden        = [bool]$Template.outOfBoxExperienceSetting.privacySettingsHidden
                eulaHidden                   = [bool]$Template.outOfBoxExperienceSetting.eulaHidden
                userType                     = $Template.outOfBoxExperienceSetting.userType
                keyboardSelectionPageSkipped = [bool]$Template.outOfBoxExperienceSetting.keyboardSelectionPageSkipped
            }
        }

        # Serialize to JSON to avoid Invoke-MgGraphRequest internal serialization issues
        $profileJson = $profileBody | ConvertTo-Json -Depth 10 -Compress
        Write-Verbose "Autopilot profile body: $profileJson"

        $newProfile = $null
        $firstError = $null
        try {
            $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -Body $profileJson -ContentType 'application/json' -ErrorAction Stop
        } catch {
            $firstError = $_
            $retryStatusCode = $null
            if ($_.Exception.Response.StatusCode) {
                $retryStatusCode = [int]$_.Exception.Response.StatusCode
            }
            $strategyErrMsg = Get-GraphErrorMessage -ErrorRecord $_
            Write-Verbose "Autopilot profile '$ProfileName' failed: $strategyErrMsg"

            if ($retryStatusCode -eq 400) {
                # Retry with safe defaults for properties that require specific licensing
                $profileBody.preprovisioningAllowed = $false
                $profileBody.hardwareHashExtractionEnabled = $false
                $retryJson = $profileBody | ConvertTo-Json -Depth 10 -Compress
                Write-Verbose "Autopilot profile retry body (safe defaults): $retryJson"

                try {
                    $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -Body $retryJson -ContentType 'application/json' -ErrorAction Stop
                    $firstError = $null
                    Write-Verbose "Autopilot profile '$ProfileName' succeeded with safe defaults"
                } catch {
                    Write-Verbose "Autopilot profile '$ProfileName' also failed on retry: $(Get-GraphErrorMessage -ErrorRecord $_)"
                }
            }
        }

        if ($firstError) { throw $firstError }

        Write-HydrationLog -Message "  Created: $ProfileName" -Level Info
        return New-HydrationResult -Name $ProfileName -Type 'AutopilotDeploymentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
    } catch {
        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
        Write-HydrationLog -Message "  Failed: $ProfileName - $errMessage" -Level Warning
        return New-HydrationResult -Name $ProfileName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status $errMessage
    }
}
