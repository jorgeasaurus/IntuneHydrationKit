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
        [switch]$Force,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [switch]$TestMode
    )

    # Use default template path if not specified
    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Enrollment"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        throw "Enrollment template directory not found: $TemplatePath"
    }

    $results = @()

    # Remove existing enrollment profiles if requested - ONLY profiles that match our templates
    if ($RemoveExisting) {
        Write-Information "Removing managed enrollment profiles..." -InformationAction Continue

        # Get managed profile names from templates
        $autopilotTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-Autopilot-Profile.json"
        $espTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-ESP-Profile.json"

        $managedAutopilotName = $null
        $managedEspName = $null

        if (Test-Path -Path $autopilotTemplatePath) {
            $autopilotTemplate = Get-Content -Path $autopilotTemplatePath -Raw | ConvertFrom-Json
            $managedAutopilotName = $autopilotTemplate.displayName
        }
        if (Test-Path -Path $espTemplatePath) {
            $espTemplate = Get-Content -Path $espTemplatePath -Raw | ConvertFrom-Json
            $managedEspName = $espTemplate.displayName
        }

        # Delete matching Autopilot profile only
        if ($managedAutopilotName) {
            try {
                $existingAutopilot = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -ErrorAction Stop
                $matchingProfile = $existingAutopilot.value | Where-Object { $_.displayName -eq $managedAutopilotName }

                if ($matchingProfile) {
                    if ($PSCmdlet.ShouldProcess($matchingProfile.displayName, "Delete Autopilot profile")) {
                        try {
                            Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($matchingProfile.id)" -ErrorAction Stop
                            Write-Information "Deleted Autopilot profile: $($matchingProfile.displayName)" -InformationAction Continue
                            $results += New-HydrationResult -Name $matchingProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'Deleted' -Status 'Success'
                        }
                        catch {
                            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                            Write-Warning "Failed to delete Autopilot profile '$($matchingProfile.displayName)': $errMessage"
                            $results += New-HydrationResult -Name $matchingProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status "Delete failed: $errMessage"
                        }
                    }
                    else {
                        $results += New-HydrationResult -Name $matchingProfile.displayName -Type 'AutopilotDeploymentProfile' -Action 'WouldDelete' -Status 'DryRun'
                    }
                }
            }
            catch {
                Write-Warning "Failed to list Autopilot profiles: $_"
            }
        }

        # Delete matching ESP profile only
        if ($managedEspName) {
            try {
                $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -ErrorAction Stop
                $matchingESP = $existingESP.value | Where-Object {
                    $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' -and
                    $_.displayName -eq $managedEspName
                }

                if ($matchingESP) {
                    if ($PSCmdlet.ShouldProcess($matchingESP.displayName, "Delete ESP profile")) {
                        try {
                            Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/deviceEnrollmentConfigurations/$($matchingESP.id)" -ErrorAction Stop
                            Write-Information "Deleted ESP profile: $($matchingESP.displayName)" -InformationAction Continue
                            $results += New-HydrationResult -Name $matchingESP.displayName -Type 'EnrollmentStatusPage' -Action 'Deleted' -Status 'Success'
                        }
                        catch {
                            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                            Write-Warning "Failed to delete ESP profile '$($matchingESP.displayName)': $errMessage"
                            $results += New-HydrationResult -Name $matchingESP.displayName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status "Delete failed: $errMessage"
                        }
                    }
                    else {
                        $results += New-HydrationResult -Name $matchingESP.displayName -Type 'EnrollmentStatusPage' -Action 'WouldDelete' -Status 'DryRun'
                    }
                }
            }
            catch {
                Write-Warning "Failed to list ESP profiles: $_"
            }
        }

        # RemoveExisting mode - only delete, don't create
        $summary = Get-ResultSummary -Results $results
        Write-Information "Enrollment profile removal complete: $($summary.Deleted) deleted, $($summary.Failed) failed" -InformationAction Continue
        return $results
    }

    # Test mode - only process Autopilot profile (first profile type)
    $processAutopilot = $true
    $processESP = -not $TestMode  # Skip ESP in test mode

    if ($TestMode) {
        Write-Information "Test mode: Processing only Autopilot profile" -InformationAction Continue
    }

    #region Windows Autopilot Deployment Profile
    $autopilotTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-Autopilot-Profile.json"

    if (Test-Path -Path $autopilotTemplatePath) {
        $autopilotTemplate = Get-Content -Path $autopilotTemplatePath -Raw | ConvertFrom-Json
        $profileName = $autopilotTemplate.displayName

        try {
            # Check if profile exists
            $existingProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$profileName'" -ErrorAction Stop

            if ($existingProfiles.value.Count -gt 0) {
                Write-Information "  Skipped: $profileName (already exists)" -InformationAction Continue
                $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $existingProfiles.value[0].id -Action 'Skipped' -Status 'Already exists'
            }
            elseif ($PSCmdlet.ShouldProcess($profileName, "Create Autopilot deployment profile")) {
                # Build profile body with all required properties
                $language = if ([string]::IsNullOrWhiteSpace($autopilotTemplate.language)) { 'en-US' } else { $autopilotTemplate.language }
                $descriptionText = if ($autopilotTemplate.description) { "$($autopilotTemplate.description) - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }
                $profileBody = @{
                    "@odata.type" = "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile"
                    displayName = $autopilotTemplate.displayName
                    description = $descriptionText
                    deviceType = $autopilotTemplate.deviceType
                    deviceNameTemplate = if ($DeviceNameTemplate) { $DeviceNameTemplate } else { $autopilotTemplate.deviceNameTemplate }
                    language = $language
                    enableWhiteGlove = $autopilotTemplate.enableWhiteGlove
                    extractHardwareHash = $autopilotTemplate.extractHardwareHash
                    hybridAzureADJoinSkipConnectivityCheck = $autopilotTemplate.hybridAzureADJoinSkipConnectivityCheck
                    outOfBoxExperienceSettings = @{
                        hidePrivacySettings = $autopilotTemplate.outOfBoxExperienceSettings.hidePrivacySettings
                        hideEULA = $autopilotTemplate.outOfBoxExperienceSettings.hideEULA
                        userType = $autopilotTemplate.outOfBoxExperienceSettings.userType
                        deviceUsageType = $autopilotTemplate.outOfBoxExperienceSettings.deviceUsageType
                        skipKeyboardSelectionPage = $autopilotTemplate.outOfBoxExperienceSettings.skipKeyboardSelectionPage
                        hideEscapeLink = $autopilotTemplate.outOfBoxExperienceSettings.hideEscapeLink
                    }
                    roleScopeTagIds = @()
                }

                $jsonBody = $profileBody | ConvertTo-Json -Depth 10
                $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -Body $jsonBody -ContentType "application/json" -ErrorAction Stop

                Write-Information "  Created: $profileName" -InformationAction Continue

                $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            Write-Error "Failed to create Autopilot profile: $_"
            $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status $_.Exception.Message
        }
    }
    #endregion

    #region Enrollment Status Page
    $espTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-ESP-Profile.json"

    if ($processESP -and (Test-Path -Path $espTemplatePath)) {
        $espTemplate = Get-Content -Path $espTemplatePath -Raw | ConvertFrom-Json
        $espName = $espTemplate.displayName

        try {
            # Check if ESP exists
            $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=displayName eq '$espName'" -ErrorAction Stop

            $customESP = $existingESP.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' -and $_.displayName -eq $espName }

            if ($customESP) {
                Write-Information "  Skipped: $espName (already exists)" -InformationAction Continue
                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Id $customESP.id -Action 'Skipped' -Status 'Already exists'
            }
            elseif ($PSCmdlet.ShouldProcess($espName, "Create Enrollment Status Page profile")) {
                # Build ESP body
                $espDescriptionText = if ($espTemplate.description) { "$($espTemplate.description) - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }
                $espBody = @{
                    "@odata.type" = "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
                    displayName = $espTemplate.displayName
                    description = $espDescriptionText
                    showInstallationProgress = $espTemplate.showInstallationProgress
                    blockDeviceSetupRetryByUser = $espTemplate.blockDeviceSetupRetryByUser
                    allowDeviceResetOnInstallFailure = $espTemplate.allowDeviceResetOnInstallFailure
                    allowLogCollectionOnInstallFailure = $espTemplate.allowLogCollectionOnInstallFailure
                    customErrorMessage = $espTemplate.customErrorMessage
                    installProgressTimeoutInMinutes = $espTemplate.installProgressTimeoutInMinutes
                    allowDeviceUseOnInstallFailure = $espTemplate.allowDeviceUseOnInstallFailure
                    trackInstallProgressForAutopilotOnly = $espTemplate.trackInstallProgressForAutopilotOnly
                    disableUserStatusTrackingAfterFirstUser = $espTemplate.disableUserStatusTrackingAfterFirstUser
                }

                $newESP = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -Body $espBody -ErrorAction Stop

                Write-Information "  Created: $espName" -InformationAction Continue

                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Id $newESP.id -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            Write-Error "Failed to create ESP profile: $_"
            $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status $_.Exception.Message
        }
    }
    #endregion

    # Summary
    $summary = Get-ResultSummary -Results $results

    Write-Information "Enrollment profile import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}