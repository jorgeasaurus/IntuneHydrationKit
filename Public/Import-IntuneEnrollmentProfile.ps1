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
    .EXAMPLE
        Import-IntuneEnrollmentProfile
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [string]$DeviceNameTemplate,

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
    # SAFETY: Only delete profiles that have "Imported by Intune-Hydration-Kit" in description
    if ($RemoveExisting) {
        # Delete matching Autopilot profiles
        try {
            $existingAutopilot = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -ErrorAction Stop
            foreach ($enrollmentProfile in $existingAutopilot.value) {
                # Safety check: Only delete if created by this kit (has hydration marker in description)
                if (-not (Test-HydrationKitObject -Description $enrollmentProfile.description -ObjectName $enrollmentProfile.displayName)) {
                    Write-Verbose "Skipping '$($enrollmentProfile.displayName)' - not created by Intune-Hydration-Kit"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($enrollmentProfile.displayName, "Delete Autopilot profile")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($enrollmentProfile.id)" -ErrorAction Stop
                        Write-HydrationLog -Message "  Deleted: $($enrollmentProfile.displayName)" -Level Info
                        $results += New-HydrationResult -Name $enrollmentProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'Deleted' -Status 'Success'
                    }
                    catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-HydrationLog -Message "  Failed: $($enrollmentProfile.displayName) - $errMessage" -Level Warning
                        $results += New-HydrationResult -Name $enrollmentProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                }
                else {
                    Write-HydrationLog -Message "  WouldDelete: $($enrollmentProfile.displayName)" -Level Info
                    $results += New-HydrationResult -Name $enrollmentProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        }
        catch {
            Write-HydrationLog -Message "Failed to list Autopilot profiles: $_" -Level Warning
        }

        # Delete matching ESP profiles
        try {
            $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -ErrorAction Stop
            $espProfiles = $existingESP.value | Where-Object {
                $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
            }

            foreach ($espProfile in $espProfiles) {
                # Safety check: Only delete if created by this kit (has hydration marker in description)
                if (-not (Test-HydrationKitObject -Description $espProfile.description -ObjectName $espProfile.displayName)) {
                    Write-Verbose "Skipping '$($espProfile.displayName)' - not created by Intune-Hydration-Kit"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($espProfile.displayName, "Delete ESP profile")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/deviceEnrollmentConfigurations/$($espProfile.id)" -ErrorAction Stop
                        Write-HydrationLog -Message "  Deleted: $($espProfile.displayName)" -Level Info
                        $results += New-HydrationResult -Name $espProfile.displayName -Type 'EnrollmentStatusPage' -Action 'Deleted' -Status 'Success'
                    }
                    catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-HydrationLog -Message "  Failed: $($espProfile.displayName) - $errMessage" -Level Warning
                        $results += New-HydrationResult -Name $espProfile.displayName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                }
                else {
                    Write-HydrationLog -Message "  WouldDelete: $($espProfile.displayName)" -Level Info
                    $results += New-HydrationResult -Name $espProfile.displayName -Type 'EnrollmentStatusPage' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        }
        catch {
            Write-HydrationLog -Message "Failed to list ESP profiles: $_" -Level Warning
        }

        return $results
    }

    #region Discover and process all enrollment templates
    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File

    foreach ($templateFile in $templateFiles) {
        $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json
        $profileName = $template.displayName
        $odataType = $template.'@odata.type'

        switch ($odataType) {
            '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile' {
                #region Windows Autopilot Deployment Profile
                try {
                    # Check if profile exists (escape single quotes for OData filter)
                    $safeProfileName = $profileName -replace "'", "''"
                    $existingProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$safeProfileName'" -ErrorAction Stop

                    if ($existingProfiles.value.Count -gt 0) {
                        Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $existingProfiles.value[0].id -Action 'Skipped' -Status 'Already exists'
                    }
                    elseif ($PSCmdlet.ShouldProcess($profileName, "Create Autopilot deployment profile")) {
                        # Update description with hydration tag (use newline to avoid API issues with dashes)
                        $template.description = if ($template.description) {
                            "$($template.description)`nImported by Intune Hydration Kit"
                        } else {
                            "Imported by Intune Hydration Kit"
                        }

                        # Apply custom device name template if provided
                        if ($DeviceNameTemplate) {
                            $template.deviceNameTemplate = $DeviceNameTemplate
                        }

                        # Convert to JSON for API call
                        $jsonBody = $template | ConvertTo-Json -Depth 10

                        $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -Body $jsonBody -ContentType "application/json" -OutputType PSObject -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $profileName" -Level Info

                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
                    }
                    else {
                        Write-HydrationLog -Message "  WouldCreate: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'WouldCreate' -Status 'DryRun'
                    }
                }
                catch {
                    Write-Error "Failed to create Autopilot profile: $_"
                    $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status $_.Exception.Message
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

                    if ($customESP) {
                        Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'EnrollmentStatusPage' -Id $customESP.id -Action 'Skipped' -Status 'Already exists'
                    }
                    elseif ($PSCmdlet.ShouldProcess($profileName, "Create Enrollment Status Page profile")) {
                        # Build ESP body
                        $espDescriptionText = if ($template.description) { "$($template.description) - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }
                        $espBody = @{
                            "@odata.type" = "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
                            displayName = $template.displayName
                            description = $espDescriptionText
                            showInstallationProgress = $template.showInstallationProgress
                            blockDeviceSetupRetryByUser = $template.blockDeviceSetupRetryByUser
                            allowDeviceResetOnInstallFailure = $template.allowDeviceResetOnInstallFailure
                            allowLogCollectionOnInstallFailure = $template.allowLogCollectionOnInstallFailure
                            customErrorMessage = $template.customErrorMessage
                            installProgressTimeoutInMinutes = $template.installProgressTimeoutInMinutes
                            allowDeviceUseOnInstallFailure = $template.allowDeviceUseOnInstallFailure
                            trackInstallProgressForAutopilotOnly = $template.trackInstallProgressForAutopilotOnly
                            disableUserStatusTrackingAfterFirstUser = $template.disableUserStatusTrackingAfterFirstUser
                        }

                        $newESP = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -Body $espBody -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $profileName" -Level Info

                        $results += New-HydrationResult -Name $profileName -Type 'EnrollmentStatusPage' -Id $newESP.id -Action 'Created' -Status 'Success'
                    }
                    else {
                        Write-HydrationLog -Message "  WouldCreate: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'EnrollmentStatusPage' -Action 'WouldCreate' -Status 'DryRun'
                    }
                }
                catch {
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
                    foreach ($depToken in $existingDEP.value) {
                        $depProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/depOnboardingSettings/$($depToken.id)/enrollmentProfiles" -ErrorAction SilentlyContinue
                        if ($depProfiles.value | Where-Object { $_.displayName -eq $profileName }) {
                            $profileExists = $true
                            $existingProfileId = ($depProfiles.value | Where-Object { $_.displayName -eq $profileName }).id
                            break
                        }
                    }

                    if ($profileExists) {
                        Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Id $existingProfileId -Action 'Skipped' -Status 'Already exists'
                    }
                    elseif ($existingDEP.value.Count -eq 0) {
                        Write-HydrationLog -Message "  Skipped: $profileName - No Apple DEP token configured" -Level Warning
                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Action 'Skipped' -Status 'No DEP token configured'
                    }
                    elseif ($PSCmdlet.ShouldProcess($profileName, "Create macOS DEP enrollment profile")) {
                        # Update description with hydration tag
                        $template.description = if ($template.description) {
                            "$($template.description)`nImported by Intune Hydration Kit"
                        } else {
                            "Imported by Intune Hydration Kit"
                        }

                        # Convert to JSON for API call
                        $jsonBody = $template | ConvertTo-Json -Depth 10

                        # Create profile under the first DEP token
                        $depTokenId = $existingDEP.value[0].id
                        $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/depOnboardingSettings/$depTokenId/enrollmentProfiles" -Body $jsonBody -ContentType "application/json" -OutputType PSObject -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $profileName" -Level Info

                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
                    }
                    else {
                        Write-HydrationLog -Message "  WouldCreate: $profileName" -Level Info
                        $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Action 'WouldCreate' -Status 'DryRun'
                    }
                }
                catch {
                    Write-HydrationLog -Message "  Failed: $profileName - $($_.Exception.Message)" -Level Warning
                    $results += New-HydrationResult -Name $profileName -Type 'MacOSDEPEnrollmentProfile' -Action 'Failed' -Status $_.Exception.Message
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