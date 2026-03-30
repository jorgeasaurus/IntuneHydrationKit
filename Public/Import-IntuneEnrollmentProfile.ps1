function Import-IntuneEnrollmentProfile {
    <#
    .SYNOPSIS
        Imports enrollment profiles
    .DESCRIPTION
        Creates Windows Autopilot deployment profiles and Enrollment Status Page configurations.
        Optionally creates Apple enrollment profiles if ABM is enabled.
    .PARAMETER TemplatePath
        Path to the enrollment template directory
    .PARAMETER DeviceNameTemplate
        Custom device naming template (default: %SERIAL%)
    .PARAMETER Platform
        Filter templates by platform. Valid values: Windows, macOS, All.
        Defaults to 'All' which imports all enrollment profile templates regardless of platform.
        Note: Enrollment profiles are available for Windows (Autopilot, ESP) and macOS (DEP).
    .EXAMPLE
        Import-IntuneEnrollmentProfile
    .EXAMPLE
        Import-IntuneEnrollmentProfile -Platform Windows
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [string]$DeviceNameTemplate,

        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'All')]
        [string[]]$Platform = @('All'),

        [Parameter()]
        [switch]$RemoveExisting
    )

    # Use default template path if not specified
    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Enrollment"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        throw "Enrollment template directory not found: $TemplatePath"
    }

    $results = @()

    # Remove existing enrollment profiles if requested
    # SAFETY: Only delete profiles that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        # Load template names to scope deletes to only profiles this kit would create
        $knownTemplateNames = Get-TemplateDisplayNames -Path $TemplatePath

        # Delete matching Autopilot profiles
        try {
            $existingAutopilot = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -ErrorAction Stop
            foreach ($enrollmentProfile in $existingAutopilot.value) {
                if (-not (Test-HydrationKitObject -Description $enrollmentProfile.description -ObjectName $enrollmentProfile.displayName)) {
                    Write-Verbose "Skipping '$($enrollmentProfile.displayName)' - not created by Intune Hydration Kit"
                    continue
                }

                $escapedPrefix = [regex]::Escape($script:ImportPrefix)
                $autopilotNameForLookup = $enrollmentProfile.displayName -replace "^$escapedPrefix", ''
                if (-not ($knownTemplateNames.Contains($enrollmentProfile.displayName) -or $knownTemplateNames.Contains($autopilotNameForLookup))) {
                    Write-Verbose "Skipping '$($enrollmentProfile.displayName)' - not in this kit's templates (may be from another tool)"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($enrollmentProfile.displayName, "Delete Autopilot profile")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($enrollmentProfile.id)" -ErrorAction Stop
                        Write-HydrationLog -Message "  Deleted: $($enrollmentProfile.displayName)" -Level Info
                        $results += New-HydrationResult -Name $enrollmentProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'Deleted' -Status 'Success'
                    } catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-HydrationLog -Message "  Failed: $($enrollmentProfile.displayName) - $errMessage" -Level Warning
                        $results += New-HydrationResult -Name $enrollmentProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                } else {
                    Write-HydrationLog -Message "  WouldDelete: $($enrollmentProfile.displayName)" -Level Info
                    $results += New-HydrationResult -Name $enrollmentProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        } catch {
            Write-HydrationLog -Message "Failed to list Autopilot profiles: $_" -Level Warning
        }

        # Delete matching ESP profiles
        try {
            $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -ErrorAction Stop
            $espProfiles = $existingESP.value | Where-Object {
                $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
            }

            foreach ($espProfile in $espProfiles) {
                if (-not (Test-HydrationKitObject -Description $espProfile.description -ObjectName $espProfile.displayName)) {
                    Write-Verbose "Skipping '$($espProfile.displayName)' - not created by Intune Hydration Kit"
                    continue
                }

                $escapedPrefix = [regex]::Escape($script:ImportPrefix)
                $espNameForLookup = $espProfile.displayName -replace "^$escapedPrefix", ''
                if (-not ($knownTemplateNames.Contains($espProfile.displayName) -or $knownTemplateNames.Contains($espNameForLookup))) {
                    Write-Verbose "Skipping '$($espProfile.displayName)' - not in this kit's templates (may be from another tool)"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($espProfile.displayName, "Delete ESP profile")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/deviceEnrollmentConfigurations/$($espProfile.id)" -ErrorAction Stop
                        Write-HydrationLog -Message "  Deleted: $($espProfile.displayName)" -Level Info
                        $results += New-HydrationResult -Name $espProfile.displayName -Type 'EnrollmentStatusPage' -Action 'Deleted' -Status 'Success'
                    } catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-HydrationLog -Message "  Failed: $($espProfile.displayName) - $errMessage" -Level Warning
                        $results += New-HydrationResult -Name $espProfile.displayName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                } else {
                    Write-HydrationLog -Message "  WouldDelete: $($espProfile.displayName)" -Level Info
                    $results += New-HydrationResult -Name $espProfile.displayName -Type 'EnrollmentStatusPage' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        } catch {
            Write-HydrationLog -Message "Failed to list ESP profiles: $_" -Level Warning
        }

        # Delete matching Autopilot Device Preparation policies (configurationPolicies with technologies = "enrollment")
        try {
            $existingPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/configurationPolicies?`$filter=technologies eq 'enrollment'" -ErrorAction Stop
            foreach ($policy in $existingPolicies.value) {
                if (-not (Test-HydrationKitObject -Description $policy.description -ObjectName $policy.name)) {
                    Write-Verbose "Skipping '$($policy.name)' - not created by Intune Hydration Kit"
                    continue
                }

                $escapedPrefix = [regex]::Escape($script:ImportPrefix)
                $prepNameForLookup = $policy.name -replace "^$escapedPrefix", ''
                if (-not ($knownTemplateNames.Contains($policy.name) -or $knownTemplateNames.Contains($prepNameForLookup))) {
                    Write-Verbose "Skipping '$($policy.name)' - not in this kit's templates (may be from another tool)"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($policy.name, "Delete Autopilot Device Preparation policy")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/configurationPolicies/$($policy.id)" -ErrorAction Stop
                        Write-HydrationLog -Message "  Deleted: $($policy.name)" -Level Info
                        $results += New-HydrationResult -Name $policy.name -Type 'AutopilotDevicePreparation' -Action 'Deleted' -Status 'Success'
                    } catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-HydrationLog -Message "  Failed: $($policy.name) - $errMessage" -Level Warning
                        $results += New-HydrationResult -Name $policy.name -Type 'AutopilotDevicePreparation' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                } else {
                    Write-HydrationLog -Message "  WouldDelete: $($policy.name)" -Level Info
                    $results += New-HydrationResult -Name $policy.name -Type 'AutopilotDevicePreparation' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        } catch {
            Write-HydrationLog -Message "Failed to list Autopilot Device Preparation policies: $_" -Level Warning
        }

        return $results
    }

    #region Discover and process all enrollment templates
    $templateFiles = Get-FilteredTemplates -Path $TemplatePath -Platform $Platform -FilterMode 'Prefix' -ResourceType "enrollment template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No $Platform enrollment templates found."
        return @()
    }

    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Error "Failed to load or parse enrollment template file '$($templateFile.FullName)': $_"
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $($_.Exception.Message)" -Level Error
            $results += New-HydrationResult -Name $templateFile.Name -Type 'EnrollmentTemplate' -Action 'Failed' -Status $_.Exception.Message
            continue
        }
        # Some templates use displayName, others use name (configurationPolicies)
        $profileName = if ($template.displayName) { "$($script:ImportPrefix)$($template.displayName)" } else { "$($script:ImportPrefix)$($template.name)" }
        $odataType = $template.'@odata.type'
        if ($template.technologies -eq 'enrollment') { $odataType = '#microsoft.graph.deviceManagementConfigurationPolicy' }

        # Skip templates with empty or missing @odata.type
        if ([string]::IsNullOrWhiteSpace($odataType)) {
            Write-HydrationLog -Message "  Skipped: $($templateFile.Name) - Missing @odata.type" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Type 'EnrollmentTemplate' -Action 'Skipped' -Status 'Missing @odata.type'
            continue
        }

        switch ($odataType) {
            '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile' {
                #region Windows Autopilot Deployment Profile
                try {
                    # Check if profile exists (escape single quotes for OData filter)
                    $safeProfileName = $profileName -replace "'", "''"
                    $existingProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$safeProfileName'" -ErrorAction Stop

                    $taggedMatch = $false
                    $existingProfileId = $null
                    if ($existingProfiles.value.Count -gt 0) {
                        $existingProfile = $existingProfiles.value[0]
                        $existingProfileId = $existingProfile.id
                        $taggedMatch = Test-HydrationKitObject -Description $existingProfile.description -ObjectName $profileName
                    }

                    if ($taggedMatch) {
                        Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $existingProfileId -Action 'Skipped' -Status 'Already exists'
                    } elseif ($PSCmdlet.ShouldProcess($profileName, "Create Autopilot deployment profile")) {
                        # Autopilot deployment profiles reject dashes in descriptions (undocumented API restriction)
                        # Strip dashes from original text first, then build tag with space separator (no dash)
                        $cleanDesc = ($template.description -replace '-', '').Trim() -replace '  +', ' '
                        $profileDescription = New-HydrationDescription -ExistingText $cleanDesc -Separator ' '

                        # Apply custom device name template if provided
                        $deviceName = if ($DeviceNameTemplate) { $DeviceNameTemplate } else { $template.deviceNameTemplate }

                        # Build profile body matching the exact format the Graph API accepts
                        # (verified against Intune console's working POST payload)
                        $profileBody = @{
                            "@odata.type"                          = "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile"
                            displayName                            = $profileName
                            description                            = $profileDescription
                            deviceNameTemplate                     = $deviceName
                            locale                                 = $template.locale
                            preprovisioningAllowed                 = [bool]$template.preprovisioningAllowed
                            deviceType                             = $template.deviceType
                            hardwareHashExtractionEnabled          = [bool]$template.hardwareHashExtractionEnabled
                            roleScopeTagIds                        = @()
                            hybridAzureADJoinSkipConnectivityCheck = [bool]$template.hybridAzureADJoinSkipConnectivityCheck
                            outOfBoxExperienceSetting              = @{
                                deviceUsageType              = $template.outOfBoxExperienceSetting.deviceUsageType
                                escapeLinkHidden             = [bool]$template.outOfBoxExperienceSetting.escapeLinkHidden
                                privacySettingsHidden        = [bool]$template.outOfBoxExperienceSetting.privacySettingsHidden
                                eulaHidden                   = [bool]$template.outOfBoxExperienceSetting.eulaHidden
                                userType                     = $template.outOfBoxExperienceSetting.userType
                                keyboardSelectionPageSkipped = [bool]$template.outOfBoxExperienceSetting.keyboardSelectionPageSkipped
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
                            Write-Verbose "Autopilot profile '$profileName' failed: $strategyErrMsg"

                            if ($retryStatusCode -eq 400) {
                                # Retry with safe defaults for properties that require specific licensing
                                $profileBody.preprovisioningAllowed = $false
                                $profileBody.hardwareHashExtractionEnabled = $false
                                $retryJson = $profileBody | ConvertTo-Json -Depth 10 -Compress
                                Write-Verbose "Autopilot profile retry body (safe defaults): $retryJson"

                                try {
                                    $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -Body $retryJson -ContentType 'application/json' -ErrorAction Stop
                                    $firstError = $null
                                    Write-Verbose "Autopilot profile '$profileName' succeeded with safe defaults"
                                } catch {
                                    Write-Verbose "Autopilot profile '$profileName' also failed on retry: $(Get-GraphErrorMessage -ErrorRecord $_)"
                                }
                            }
                        }

                        if ($firstError) { throw $firstError }

                        Write-HydrationLog -Message "  Created: $profileName" -Level Info

                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
                    } else {
                        Write-HydrationLog -Message "  WouldCreate: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'WouldCreate' -Status 'DryRun'
                    }
                } catch {
                    $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $profileName - $errMessage" -Level Warning
                    $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status $errMessage
                }
                #endregion
            }

            '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' {
                #region Enrollment Status Page
                try {
                    # Check if ESP exists (escape single quotes for OData filter)
                    $safeEspName = $profileName -replace "'", "''"
                    $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=displayName eq '$safeEspName'" -ErrorAction Stop

                    $customESP = $existingESP.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' -and $_.displayName -eq $profileName }

                    $taggedMatch = $false
                    $espId = $null
                    if ($customESP) {
                        $espId = $customESP.id
                        $taggedMatch = Test-HydrationKitObject -Description $customESP.description -ObjectName $profileName
                    }

                    if ($taggedMatch) {
                        Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'EnrollmentStatusPage' -Id $espId -Action 'Skipped' -Status 'Already exists'
                    } elseif ($PSCmdlet.ShouldProcess($profileName, "Create Enrollment Status Page profile")) {
                        # Build ESP body
                        $espDescriptionText = New-HydrationDescription -ExistingText $template.description
                        $espBody = @{
                            "@odata.type"                           = "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
                            displayName                             = "$($script:ImportPrefix)$($template.displayName)"
                            description                             = $espDescriptionText
                            showInstallationProgress                = $template.showInstallationProgress
                            blockDeviceSetupRetryByUser             = $template.blockDeviceSetupRetryByUser
                            allowDeviceResetOnInstallFailure        = $template.allowDeviceResetOnInstallFailure
                            allowLogCollectionOnInstallFailure      = $template.allowLogCollectionOnInstallFailure
                            customErrorMessage                      = $template.customErrorMessage
                            installProgressTimeoutInMinutes         = $template.installProgressTimeoutInMinutes
                            allowDeviceUseOnInstallFailure          = $template.allowDeviceUseOnInstallFailure
                            trackInstallProgressForAutopilotOnly    = $template.trackInstallProgressForAutopilotOnly
                            disableUserStatusTrackingAfterFirstUser = $template.disableUserStatusTrackingAfterFirstUser
                        }

                        $newESP = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -Body $espBody -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $profileName" -Level Info

                        $results += New-HydrationResult -Name $profileName -Type 'EnrollmentStatusPage' -Id $newESP.id -Action 'Created' -Status 'Success'
                    } else {
                        Write-HydrationLog -Message "  WouldCreate: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'EnrollmentStatusPage' -Action 'WouldCreate' -Status 'DryRun'
                    }
                } catch {
                    Write-HydrationLog -Message "  Failed: $profileName - $($_.Exception.Message)" -Level Warning
                    $results += New-HydrationResult -Name $profileName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status $_.Exception.Message
                }
                #endregion
            }

            '#microsoft.graph.depMacOSEnrollmentProfile' {
                #region macOS DEP Enrollment Profile
                try {
                    # Check if macOS DEP profile exists
                    $safeProfileName = $profileName -replace "'", "''"
                    $existingDEP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/depOnboardingSettings" -ErrorAction Stop

                    # Find enrollment profiles for each DEP token
                    $profileExists = $false
                    $taggedMatch = $false
                    $existingProfileId = $null
                    foreach ($depToken in $existingDEP.value) {
                        $depProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/depOnboardingSettings/$($depToken.id)/enrollmentProfiles" -ErrorAction SilentlyContinue
                        $matchingProfile = $depProfiles.value | Where-Object { $_.displayName -eq $profileName }
                        if ($matchingProfile) {
                            $profileExists = $true
                            $existingProfileId = $matchingProfile.id
                            $taggedMatch = Test-HydrationKitObject -Description $matchingProfile.description -ObjectName $profileName
                            break
                        }
                    }

                    if ($taggedMatch) {
                        Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Id $existingProfileId -Action 'Skipped' -Status 'Already exists'
                    } elseif ($existingDEP.value.Count -eq 0) {
                        Write-HydrationLog -Message "  Skipped: $profileName - No Apple DEP token configured" -Level Warning
                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Action 'Skipped' -Status 'No DEP token configured'
                    } elseif ($PSCmdlet.ShouldProcess($profileName, "Create macOS DEP enrollment profile")) {
                        # Update description with hydration tag
                        $template.description = New-HydrationDescription -ExistingText $template.description

                        # Convert to JSON for API call
                        $jsonBody = $template | ConvertTo-Json -Depth 10

                        # Create profile under the first DEP token
                        $depTokenId = $existingDEP.value[0].id
                        $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/depOnboardingSettings/$depTokenId/enrollmentProfiles" -Body $jsonBody -ContentType "application/json" -OutputType PSObject -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $profileName" -Level Info

                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
                    } else {
                        Write-HydrationLog -Message "  WouldCreate: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Action 'WouldCreate' -Status 'DryRun'
                    }
                } catch {
                    Write-HydrationLog -Message "  Failed: $profileName - $($_.Exception.Message)" -Level Warning
                    $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Action 'Failed' -Status $_.Exception.Message
                }
                #endregion
            }

            '#microsoft.graph.deviceManagementConfigurationPolicy' {
                #region Windows Autopilot Device Preparation Policy

                try {
                    # Check if policy exists - filter by technologies (name filter not supported)
                    $existingPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/configurationPolicies?`$filter=technologies eq 'enrollment'" -ErrorAction Stop

                    $existingPolicy = $existingPolicies.value | Where-Object { $_.name -eq $profileName }

                    $taggedMatch = $false
                    $existingPolicyId = $null
                    if ($existingPolicy) {
                        $existingPolicyId = $existingPolicy.id
                        $taggedMatch = Test-HydrationKitObject -Description $existingPolicy.description -ObjectName $profileName
                    }

                    if ($taggedMatch) {
                        Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDevicePreparation' -Id $existingPolicyId -Action 'Skipped' -Status 'Already exists'
                    } elseif ($PSCmdlet.ShouldProcess($profileName, "Create Autopilot device preparation policy")) {
                        # Update description with hydration tag
                        $policyDescription = New-HydrationDescription -ExistingText $template.description

                        # Build the policy body
                        $policyBody = @{
                            name              = $template.name
                            description       = $policyDescription
                            platforms         = $template.platforms
                            technologies      = $template.technologies
                            templateReference = $template.templateReference
                            settings          = if ($template.settings) { $template.settings } else { @() }
                        } | ConvertTo-Json -Depth 20

                        $newPolicy = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/configurationPolicies" -Body $policyBody -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $profileName" -Level Info

                        # For "Windows Autopilot device preparation - User Driven", assign the device preparation group
                        if ($profileName -eq "$($script:ImportPrefix)Windows Autopilot device preparation - User Driven") {
                            try {
                                # Check if the Autopilot device preparation group exists
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

                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDevicePreparation' -Id $newPolicy.id -Action 'Created' -Status 'Success'
                    } else {
                        Write-HydrationLog -Message "  WouldCreate: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDevicePreparation' -Action 'WouldCreate' -Status 'DryRun'
                    }
                } catch {
                    $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $profileName - $errMessage" -Level Warning
                    $results += New-HydrationResult -Name $profileName -Type 'AutopilotDevicePreparation' -Action 'Failed' -Status $errMessage
                }
                #endregion
            }

            default {
                Write-HydrationLog -Message "  Skipped: $profileName - Unknown profile type: $odataType" -Level Warning
                $results += New-HydrationResult -Name $profileName -Type 'Unknown' -Action 'Skipped' -Status "Unknown @odata.type: $odataType"
            }
        }
    }
    #endregion

    return $results
}