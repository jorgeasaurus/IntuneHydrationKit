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

    #region Windows Autopilot Deployment Profile
    $autopilotTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-Autopilot-Profile.json"

    if (Test-Path -Path $autopilotTemplatePath) {
        $autopilotTemplate = Get-Content -Path $autopilotTemplatePath -Raw | ConvertFrom-Json
        $profileName = $autopilotTemplate.displayName

        try {
            # Check if profile exists (escape single quotes for OData filter)
            $safeProfileName = $profileName -replace "'", "''"
            $existingProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$safeProfileName'" -ErrorAction Stop

            if ($existingProfiles.value.Count -gt 0) {
                Write-HydrationLog -Message "  Skipped: $profileName" -Level Info
                $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $existingProfiles.value[0].id -Action 'Skipped' -Status 'Already exists'
            }
            elseif ($PSCmdlet.ShouldProcess($profileName, "Create Autopilot deployment profile")) {
                # Read template directly
                $templateObj = Get-Content -Path $autopilotTemplatePath -Raw | ConvertFrom-Json

                # Update description with hydration tag (use newline to avoid API issues with dashes)
                $templateObj.description = if ($templateObj.description) {
                    "$($templateObj.description)`nImported by Intune Hydration Kit"
                } else {
                    "Imported by Intune Hydration Kit"
                }

                # Apply custom device name template if provided
                if ($DeviceNameTemplate) {
                    $templateObj.deviceNameTemplate = $DeviceNameTemplate
                }

                # Convert to JSON for API call
                $jsonBody = $templateObj | ConvertTo-Json -Depth 10

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
    }
    #endregion

    #region Enrollment Status Page
    $espTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-ESP-Profile.json"

    if (Test-Path -Path $espTemplatePath) {
        $espTemplate = Get-Content -Path $espTemplatePath -Raw | ConvertFrom-Json
        $espName = $espTemplate.displayName

        try {
            # Check if ESP exists (escape single quotes for OData filter)
            $safeEspName = $espName -replace "'", "''"
            $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=displayName eq '$safeEspName'" -ErrorAction Stop

            $customESP = $existingESP.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' -and $_.displayName -eq $espName }

            if ($customESP) {
                Write-HydrationLog -Message "  Skipped: $espName" -Level Info
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

                Write-HydrationLog -Message "  Created: $espName" -Level Info

                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Id $newESP.id -Action 'Created' -Status 'Success'
            }
            else {
                Write-HydrationLog -Message "  WouldCreate: $espName" -Level Info
                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            Write-HydrationLog -Message "  Failed: $espName - $($_.Exception.Message)" -Level Warning
            $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status $_.Exception.Message
        }
    }
    #endregion

    return $results
}