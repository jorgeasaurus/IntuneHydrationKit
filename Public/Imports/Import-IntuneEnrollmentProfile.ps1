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
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Enrollment template directory not found: $TemplatePath"),
            'EnrollmentTemplateNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $TemplatePath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $results = @()
    $templateFiles = Get-FilteredTemplates -Path $TemplatePath -Platform $Platform -FilterMode 'Prefix' -ResourceType "enrollment template"

    if ((-not $templateFiles -or $templateFiles.Count -eq 0) -and -not $RemoveExisting) {
        Write-Warning "No $Platform enrollment templates found."
        return @()
    }

    # Remove existing enrollment profiles if requested
    # SAFETY: Only delete profiles that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        # Load template names to scope deletes to only profiles this kit would create
        $knownTemplateNames = if ($templateFiles -and $templateFiles.Count -gt 0) {
            Get-TemplateDisplayNames -TemplateFiles $templateFiles
        } else {
            [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        $includeWindowsEnrollment = -not $Platform -or $Platform -contains 'All' -or $Platform -contains 'Windows'
        $includeMacOSEnrollment = -not $Platform -or $Platform -contains 'All' -or $Platform -contains 'macOS'
        $macOSKnownTemplateNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        if ($includeWindowsEnrollment -and $knownTemplateNames.Count -eq 0) {
            $statusMessage = 'No Windows enrollment templates found; enrollment profile delete skipped to avoid unscoped cleanup'
            Write-HydrationLog -Message "  Skipped: Windows enrollment profiles - $statusMessage" -Level Warning
            $results += New-HydrationResult -Name 'Windows enrollment profiles' -Type 'EnrollmentProfile' -Action 'Skipped' -Status $statusMessage
            $includeWindowsEnrollment = $false
        }

        if ($includeMacOSEnrollment) {
            $macOSTemplateFiles = @(Get-FilteredTemplates -Path $TemplatePath -Platform @('macOS') -FilterMode 'Prefix' -ResourceType "enrollment template")
            if ($macOSTemplateFiles.Count -gt 0) {
                $macOSKnownTemplateNames = Get-TemplateDisplayNames -TemplateFiles $macOSTemplateFiles
            }

            if ($macOSKnownTemplateNames.Count -eq 0) {
                $statusMessage = 'No macOS enrollment templates found; DEP enrollment profile delete skipped to avoid unscoped cleanup'
                Write-HydrationLog -Message "  Skipped: macOS DEP enrollment profiles - $statusMessage" -Level Warning
                $results += New-HydrationResult -Name 'macOS DEP enrollment profiles' -Type 'MacOSDEPEnrollmentProfile' -Action 'Skipped' -Status $statusMessage
                $includeMacOSEnrollment = $false
            }
        }

        if ($includeWindowsEnrollment) {
            # Canonical delete pipeline: enumerate -> marker/template-scoped decision -> batched DELETE
            $windowsDeleteTargets = @(
                @{ Endpoint = 'beta/deviceManagement/windowsAutopilotDeploymentProfiles'; Type = 'AutopilotDeploymentProfile'; Label = 'Autopilot profiles' },
                @{
                    Endpoint        = 'beta/deviceManagement/deviceEnrollmentConfigurations'
                    Type            = 'EnrollmentStatusPage'
                    Label           = 'ESP profiles'
                    CandidateFilter = {
                        param($candidate)
                        [string]$candidate.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
                    }
                },
                @{ Endpoint = "beta/deviceManagement/configurationPolicies?`$filter=technologies eq 'enrollment'"; Type = 'AutopilotDevicePreparation'; Label = 'Autopilot Device Preparation policies' }
            )

            foreach ($target in $windowsDeleteTargets) {
                $candidateParams = @{
                    Endpoint           = $target.Endpoint
                    KnownTemplateNames = $knownTemplateNames
                }
                if ($target.CandidateFilter) {
                    $candidateParams.CandidateFilter = $target.CandidateFilter
                }

                $deleteCandidates = @(Get-HydrationDeleteCandidates @candidateParams)
                if ($deleteCandidates.Count -eq 0) {
                    Write-Verbose "No $($target.Label) found to delete"
                    continue
                }

                $results += Invoke-HydrationDeleteCandidates -Candidates $deleteCandidates -ResultType $target.Type -Label $target.Label
            }
        }

        if ($includeMacOSEnrollment) {
            # macOS DEP profiles are nested under depOnboardingSettings/{token}/enrollmentProfiles.
            # Enumerate the token-scoped profiles, then use the canonical candidate/delete path.
            try {
                $depTokens = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/depOnboardingSettings?`$select=id,displayName" -ErrorAction Stop
                $depProfileObjects = @()
                foreach ($depToken in $depTokens.value) {
                    try {
                        $depProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/depOnboardingSettings/$($depToken.id)/enrollmentProfiles?`$select=id,displayName,description" -ErrorAction Stop
                    } catch {
                        Write-HydrationLog -Message "Failed to list macOS DEP enrollment profiles for DEP token '$($depToken.displayName)': $_" -Level Warning
                        continue
                    }

                    foreach ($depProfile in $depProfiles.value) {
                        $depProfile | Add-Member -NotePropertyName FullObjectUri -NotePropertyValue "beta/deviceManagement/depOnboardingSettings/$($depToken.id)/enrollmentProfiles/$($depProfile.id)" -Force
                        $depProfile | Add-Member -NotePropertyName DeleteUrl -NotePropertyValue "/deviceManagement/depOnboardingSettings/$($depToken.id)/enrollmentProfiles/$($depProfile.id)" -Force
                        $depProfileObjects += $depProfile
                    }
                }

                $depDeleteCandidates = @(Get-HydrationDeleteCandidates -InputObject $depProfileObjects -KnownTemplateNames $macOSKnownTemplateNames)
                $results += Invoke-HydrationDeleteCandidates -Candidates $depDeleteCandidates -ResultType 'MacOSDEPEnrollmentProfile' -Label 'macOS DEP enrollment profiles'
            } catch {
                Write-HydrationLog -Message "Failed to list DEP onboarding settings: $_" -Level Warning
            }
        }

        return $results
    }

    #region Discover and process all enrollment templates
    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Failed to load or parse enrollment template file '$($templateFile.FullName)': $($_.Exception.Message)", $_.Exception),
                'TemplateParseError',
                [System.Management.Automation.ErrorCategory]::ParserError,
                $templateFile.FullName
            )
            $PSCmdlet.WriteError($errorRecord)
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $($_.Exception.Message)" -Level Error
            $results += New-HydrationResult -Name $templateFile.Name -Type 'EnrollmentTemplate' -Action 'Failed' -Status $_.Exception.Message
            continue
        }
        # Some templates use displayName, others use name (configurationPolicies)
        $templateBaseName = if ($template.displayName) { $template.displayName } else { $template.name }
        $profileName = "$($script:ImportPrefix)$templateBaseName"
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
                $results += Import-HydrationAutopilotProfile -Template $template -ProfileName $profileName -TemplateBaseName $templateBaseName -DeviceNameTemplate $DeviceNameTemplate
            }

            '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' {
                $results += Import-HydrationEnrollmentStatusPage -Template $template -ProfileName $profileName -TemplateBaseName $templateBaseName
            }

            '#microsoft.graph.depMacOSEnrollmentProfile' {
                $results += Import-HydrationDepEnrollmentProfile -Template $template -ProfileName $profileName -TemplateBaseName $templateBaseName
            }

            '#microsoft.graph.deviceManagementConfigurationPolicy' {
                $results += Import-HydrationDevicePreparationPolicy -Template $template -ProfileName $profileName -TemplateBaseName $templateBaseName
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
