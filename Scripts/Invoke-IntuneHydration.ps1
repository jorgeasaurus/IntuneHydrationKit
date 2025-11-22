#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Main orchestrator script for Intune tenant hydration
.DESCRIPTION
    Executes the complete hydration workflow including authentication,
    pre-flight checks, and import of all baseline configurations.
.PARAMETER SettingsPath
    Path to the settings JSON file
.PARAMETER WhatIf
    Run in dry-run mode without making changes to Intune
.PARAMETER Force
    Force update of existing configurations
.EXAMPLE
    ./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json
.EXAMPLE
    ./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -WhatIf
.EXAMPLE
    ./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$SettingsPath,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Resolve paths
$scriptRoot = $PSScriptRoot
$moduleRoot = Split-Path -Path $scriptRoot -Parent

# Import the module
$modulePath = Join-Path -Path $moduleRoot -ChildPath 'IntuneHydrationKit.psd1'
if (Test-Path -Path $modulePath) {
    Import-Module -Name $modulePath -Force
}
else {
    throw "Module not found at: $modulePath"
}

# Import helpers
$helpersPath = Join-Path -Path $scriptRoot -ChildPath 'Modules/Helpers.psm1'
Import-Module -Name $helpersPath -Force

#region Main Execution

try {
    # Initialize logging
    $logsPath = Join-Path -Path $moduleRoot -ChildPath 'Logs'
    Initialize-HydrationLogging -LogPath $logsPath -EnableVerbose:($VerbosePreference -eq 'Continue')

    Write-HydrationLog -Message "=== Intune Hydration Kit Started ===" -Level Info

    # Load settings
    $settings = Import-HydrationSettings -Path $SettingsPath
    Write-HydrationLog -Message "Loaded settings for tenant: $($settings.tenant.tenantId)" -Level Info

    if ($WhatIfPreference) {
        Write-HydrationLog -Message "Running in DRY-RUN mode - no changes will be made" -Level Warning
    }

    # Initialize results tracking
    $allResults = @()

    # Step 1: Authenticate
    Write-HydrationLog -Message "Step 1: Authenticating to Microsoft Graph" -Level Info

    $authParams = @{
        TenantId = $settings.tenant.tenantId
    }

    # Add environment if specified
    if ($settings.authentication.environment) {
        $authParams['Environment'] = $settings.authentication.environment
    }

    if ($settings.authentication.mode -eq 'certificate') {
        $authParams['ClientId'] = $settings.authentication.clientId
        $authParams['CertificateThumbprint'] = $settings.authentication.certificateThumbprint
    }
    else {
        $authParams['Interactive'] = $true
    }

    if (-not $WhatIfPreference) {
        Connect-IntuneHydration @authParams
    }
    else {
        Write-HydrationLog -Message "[DRY-RUN] Would connect to tenant: $($settings.tenant.tenantId)" -Level Info
    }

    # Step 2: Pre-flight checks
    Write-HydrationLog -Message "Step 2: Running pre-flight checks" -Level Info

    if (-not $WhatIfPreference) {
        Test-IntunePrerequisites | Out-Null
    }
    else {
        Write-HydrationLog -Message "[DRY-RUN] Would validate Intune license and MDM authority" -Level Info
    }

    # Step 3: Create Dynamic Groups
    if ($settings.imports.dynamicGroups) {
        Write-HydrationLog -Message "Step 3: Creating Dynamic Groups" -Level Info

        $groupsTemplatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups'

        if (Test-Path -Path $groupsTemplatePath) {
            $groupTemplates = Get-ChildItem -Path $groupsTemplatePath -Filter "*.json" -File

            foreach ($templateFile in $groupTemplates) {
                $templateContent = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json

                # Handle templates with multiple groups
                $groups = if ($templateContent.groups) { $templateContent.groups } else { @($templateContent) }

                foreach ($groupDef in $groups) {
                    if ($PSCmdlet.ShouldProcess($groupDef.displayName, "Create dynamic group")) {
                        $groupResult = New-IntuneDynamicGroup -DisplayName $groupDef.displayName -Description $groupDef.description -MembershipRule $groupDef.membershipRule

                        $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $groupDef.displayName -Action $groupResult.Action -Id $groupResult.Id -Details $groupResult.Reason
                        Write-HydrationLog -Message "$($groupResult.Action) group: $($groupDef.displayName)" -Level Info
                    }
                }
            }
        }
        else {
            Write-HydrationLog -Message "Dynamic Groups template directory not found" -Level Warning
        }
    }

    # Step 4: Create Device Filters
    if ($settings.imports.deviceFilters -ne $false) {
        Write-HydrationLog -Message "Step 4: Creating Device Filters" -Level Info

        if ($PSCmdlet.ShouldProcess("Device Filters", "Create device filters")) {
            $filterResults = Import-IntuneDeviceFilter
            foreach ($result in $filterResults) {
                $allResults += New-HydrationResult -Type 'DeviceFilter' -Name $result.Name -Action $result.Action -Id $result.Id -Details $result.Status
            }
        }
    }

    # Step 5: Import OpenIntuneBaseline
    if ($settings.imports.openIntuneBaseline) {
        Write-HydrationLog -Message "Step 5: Importing OpenIntuneBaseline policies" -Level Info

        $baselineParams = @{}

        if ($settings.openIntuneBaseline.downloadPath) {
            $baselineParams['BaselinePath'] = $settings.openIntuneBaseline.downloadPath
        }

        if ($PSCmdlet.ShouldProcess("OpenIntuneBaseline", "Import baseline policies")) {
            $baselineResults = Import-IntuneBaseline @baselineParams
            foreach ($result in $baselineResults) {
                $allResults += New-HydrationResult -Type 'BaselinePolicy' -Name $result.Name -Action $result.Action -Id $null -Details $result.Status
            }
        }
    }

    # Step 6: Import Compliance Templates (local)
    if ($settings.imports.complianceTemplates) {
        Write-HydrationLog -Message "Step 6: Importing Compliance templates" -Level Info

        if ($PSCmdlet.ShouldProcess("Compliance Templates", "Import compliance policies")) {
            $complianceResults = Import-IntuneCompliancePolicy
            foreach ($result in $complianceResults) {
                $allResults += New-HydrationResult -Type $result.Type -Name $result.Name -Action $result.Action -Id $null -Details $result.Status
            }
        }
    }

    # Step 7: Import Notification Templates
    if ($settings.imports.notificationTemplates) {
        Write-HydrationLog -Message "Step 7: Importing Notification Templates" -Level Info

        if ($PSCmdlet.ShouldProcess("Notification Templates", "Import notification templates")) {
            $notificationResults = Import-IntuneNotificationTemplate
            foreach ($result in $notificationResults) {
                $resultType = if ([string]::IsNullOrWhiteSpace($result.Type)) { 'NotificationTemplate' } else { $result.Type }
                $allResults += New-HydrationResult -Type $resultType -Name $result.Name -Action $result.Action -Id $null -Details $result.Status
            }
        }
    }

    # Step 8: Import App Protection Policies (MAM)
    if ($settings.imports.appProtection) {
        Write-HydrationLog -Message "Step 8: Importing App Protection policies" -Level Info

        if ($PSCmdlet.ShouldProcess("App Protection", "Import app protection policies")) {
            $mamResults = Import-IntuneAppProtectionPolicy
            foreach ($result in $mamResults) {
                $allResults += New-HydrationResult -Type $result.Type -Name $result.Name -Action $result.Action -Id $null -Details $result.Status
            }
        }
    }

    # Step 9: Import Enrollment Profiles
    if ($settings.imports.enrollmentProfiles) {
        Write-HydrationLog -Message "Step 9: Importing Enrollment Profiles" -Level Info

        if ($PSCmdlet.ShouldProcess("Enrollment Profiles", "Import enrollment profiles")) {
            $enrollmentResults = Import-IntuneEnrollmentProfile
            foreach ($result in $enrollmentResults) {
                $allResults += New-HydrationResult -Type $result.Type -Name $result.Name -Action $result.Action -Id $result.Id -Details $result.Status
            }
        }
    }

    # Step 10: Import Conditional Access Starter Pack
    if ($settings.imports.conditionalAccess) {
        Write-HydrationLog -Message "Step 10: Importing Conditional Access Starter Pack" -Level Info

        if ($PSCmdlet.ShouldProcess("Conditional Access", "Import CA policies (disabled)")) {
            $caResults = Import-IntuneConditionalAccessPolicy
            foreach ($result in $caResults) {
                $allResults += New-HydrationResult -Type 'ConditionalAccessPolicy' -Name $result.Name -Action $result.Action -Id $result.Id -Details "$($result.Status) - State: $($result.State)"
            }
        }
    }

    # Step 11: Generate Summary Report
    Write-HydrationLog -Message "Step 11: Generating Summary Report" -Level Info

    $reportsPath = Join-Path -Path $moduleRoot -ChildPath $settings.reporting.outputPath
    if (-not (Test-Path -Path $reportsPath)) {
        New-Item -Path $reportsPath -ItemType Directory -Force | Out-Null
    }

    $summary = Get-ResultSummary -Results $allResults

    # Generate markdown report
    $reportPath = Join-Path -Path $reportsPath -ChildPath "Hydration-Summary.md"
    $jsonReportPath = $null
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $reportContent = @"
# Intune Hydration Summary

**Generated:** $timestamp
**Tenant:** $($settings.tenant.tenantId)
**Environment:** $($settings.authentication.environment)
**Mode:** $(if ($WhatIfPreference) { 'Dry-Run' } else { 'Live' })

## Summary

| Metric | Count |
|--------|-------|
| Total Operations | $($summary.Total) |
| Created | $($summary.Created) |
| Updated | $($summary.Updated) |
| Skipped | $($summary.Skipped) |
| Failed | $($summary.Failed) |

## Details by Type

"@

    foreach ($type in $summary.ByType.Keys) {
        $typeSummary = $summary.ByType[$type]
        $reportContent += @"

### $type
- Created: $($typeSummary.Created)
- Updated: $($typeSummary.Updated)
- Skipped: $($typeSummary.Skipped)
- Failed: $($typeSummary.Failed)

"@
    }

    if ($allResults.Count -gt 0) {
        $reportContent += @"

## All Operations

| Timestamp | Type | Name | Action | ID | Details |
|-----------|------|------|--------|-----|---------|
"@

        foreach ($result in $allResults) {
            $reportContent += "| $($result.Timestamp) | $($result.Type) | $($result.Name) | $($result.Action) | $($result.Id) | $($result.Details) |`n"
        }
    }

    $reportContent += @"

## Important Notes

- **Conditional Access policies** were created in **DISABLED** state. Review and enable as needed.
- **OpenIntuneBaseline policies** were imported using IntuneManagement module.
- Review all configurations before enabling in production.

"@

    $reportContent | Out-File -FilePath $reportPath -Encoding utf8
    Write-HydrationLog -Message "Summary report written to: $reportPath" -Level Info

    # Also write JSON if requested
    if ('json' -in $settings.reporting.formats) {
        $jsonReportPath = Join-Path -Path $reportsPath -ChildPath "Hydration-Summary.json"
        @{
            Timestamp = $timestamp
            Tenant = $settings.tenant.tenantId
            Environment = $settings.authentication.environment
            Mode = if ($WhatIfPreference) { 'DryRun' } else { 'Live' }
            Summary = $summary
            Results = $allResults
        } | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReportPath -Encoding utf8
        Write-HydrationLog -Message "JSON report written to: $jsonReportPath" -Level Info
    }

    Write-HydrationLog -Message "=== Intune Hydration Kit Completed ===" -Level Info

    # Friendly console summary
    Write-Host ""
    Write-Host "---------------- Summary ----------------" -ForegroundColor Cyan
    Write-Host ("Created: {0} | Updated: {1} | Skipped: {2} | Failed: {3}" -f $summary.Created, $summary.Updated, $summary.Skipped, $summary.Failed) -ForegroundColor Cyan
    foreach ($type in $summary.ByType.Keys) {
        $t = $summary.ByType[$type]
        Write-Host ("  • {0}: {1} created, {2} updated, {3} skipped, {4} failed" -f $type, $t.Created, $t.Updated, $t.Skipped, $t.Failed) -ForegroundColor Gray
    }
    Write-Host "Reports: $reportPath" -ForegroundColor Green
    if ($jsonReportPath) {
        Write-Host "JSON:    $jsonReportPath" -ForegroundColor Green
    }
    Write-Host "----------------------------------------" -ForegroundColor Cyan

    # Exit with appropriate code
    if ($summary.Failed -gt 0) {
        Write-HydrationLog -Message "Completed with $($summary.Failed) failures" -Level Warning
        exit 1
    }
    else {
        Write-HydrationLog -Message "Completed successfully: $($summary.Created) created, $($summary.Skipped) skipped" -Level Info
        exit 0
    }
}
catch {
    Write-HydrationLog -Message "Fatal error: $_" -Level Error
    Write-Error $_
    exit 1
}

#endregion
