function Import-HydrationEnrollmentStatusPage {
    <#
    .SYNOPSIS
        Creates an Enrollment Status Page configuration from a template.
    .DESCRIPTION
        Skips creation when any ESP with a matching prefixed or legacy name exists.
    .PARAMETER Template
        Parsed enrollment template object.
    .PARAMETER ProfileName
        Prefixed profile display name.
    .PARAMETER TemplateBaseName
        Legacy unprefixed template name.
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
        [string]$TemplateBaseName
    )

    try {
        # Check if ESP exists - check both prefixed and unprefixed names (backward compat)
        $safeEspName = $ProfileName -replace "'", "''"
        $espFilter = "displayName eq '$safeEspName'"
        if (-not [string]::IsNullOrWhiteSpace($TemplateBaseName) -and $TemplateBaseName -ne $ProfileName) {
            $safeOrigEspName = $TemplateBaseName -replace "'", "''"
            $espFilter += " or displayName eq '$safeOrigEspName'"
        }
        $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=$espFilter" -ErrorAction Stop

        $espCandidates = @($existingESP.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' })
        $existingMatch = Select-HydrationExistingMatch -Candidates $espCandidates -Name $ProfileName -LegacyName $TemplateBaseName -PreferTagged
        $espId = $existingMatch.id

        if ($espId) {
            # Verify the ESP still exists (handles eventual consistency after deletes)
            if (-not (Test-GraphResourceExists -Uri "beta/deviceManagement/deviceEnrollmentConfigurations/$espId")) {
                Write-Verbose "ESP '$ProfileName' (ID: $espId) no longer exists - proceeding to create"
                $espId = $null
            }
        }

        if ($espId) {
            Write-HydrationLog -Message "  Skipped: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'EnrollmentStatusPage' -Id $espId -Action 'Skipped' -Status 'Already exists'
        }

        if (-not $PSCmdlet.ShouldProcess($ProfileName, "Create Enrollment Status Page profile")) {
            Write-HydrationLog -Message "  WouldCreate: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'EnrollmentStatusPage' -Action 'WouldCreate' -Status 'DryRun'
        }

        $espDescriptionText = New-HydrationDescription -ExistingText $Template.description
        $espBody = @{
            "@odata.type"                           = "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
            displayName                             = $ProfileName
            description                             = $espDescriptionText
            showInstallationProgress                = $Template.showInstallationProgress
            blockDeviceSetupRetryByUser             = $Template.blockDeviceSetupRetryByUser
            allowDeviceResetOnInstallFailure        = $Template.allowDeviceResetOnInstallFailure
            allowLogCollectionOnInstallFailure      = $Template.allowLogCollectionOnInstallFailure
            customErrorMessage                      = $Template.customErrorMessage
            installProgressTimeoutInMinutes         = $Template.installProgressTimeoutInMinutes
            allowDeviceUseOnInstallFailure          = $Template.allowDeviceUseOnInstallFailure
            trackInstallProgressForAutopilotOnly    = $Template.trackInstallProgressForAutopilotOnly
            disableUserStatusTrackingAfterFirstUser = $Template.disableUserStatusTrackingAfterFirstUser
        }

        $newESP = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -Body $espBody -ErrorAction Stop

        Write-HydrationLog -Message "  Created: $ProfileName" -Level Info
        return New-HydrationResult -Name $ProfileName -Type 'EnrollmentStatusPage' -Id $newESP.id -Action 'Created' -Status 'Success'
    } catch {
        Write-HydrationLog -Message "  Failed: $ProfileName - $($_.Exception.Message)" -Level Warning
        return New-HydrationResult -Name $ProfileName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status $_.Exception.Message
    }
}
