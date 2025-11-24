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

# Resolve paths - script is in module root
$moduleRoot = $PSScriptRoot

# Import the module
$modulePath = Join-Path -Path $moduleRoot -ChildPath 'IntuneHydrationKit.psd1'
if (Test-Path -Path $modulePath) {
    Import-Module -Name $modulePath -Force
}
else {
    throw "Module not found at: $modulePath"
}

#region Main Execution

try {
    # Load settings first to apply options
    $settings = Import-HydrationSettings -Path $SettingsPath

    # Display current settings
    Write-Host "Loaded settings from: $SettingsPath" -InformationAction Continue
    Write-Host "Target Tenant: $($settings.tenant.tenantId)" -InformationAction Continue
    Write-Host "Authentication Mode: $($settings.authentication.mode)" -InformationAction Continue
    Write-Host "Options:" -InformationAction Continue
    Write-Host ($settings.options | Out-String) -InformationAction Continue
    Write-Host "Imports Enabled:" -InformationAction Continue
    Write-Host ($settings.imports | Out-String) -InformationAction Continue

    # Apply options from settings file (command-line switches take precedence)
    # Initialize variables with defaults (these will be set below if $settings.options exists)
    $createEnabled = $false
    $RemoveExisting = $false
    $TestMode = $false

    if ($settings.options) {
        # Validate CUD options - only one can be true
        $createEnabled = $settings.options.create -eq $true
        $updateEnabled = $settings.options.update -eq $true
        $deleteEnabled = $settings.options.delete -eq $true

        $trueCount = @($createEnabled, $updateEnabled, $deleteEnabled) | Where-Object { $_ -eq $true } | Measure-Object | Select-Object -ExpandProperty Count

        if ($trueCount -gt 1) {
            throw "Only one of 'create', 'update', or 'delete' options can be true. Current settings: create=$createEnabled, update=$updateEnabled, delete=$deleteEnabled"
        }

        if ($trueCount -eq 0) {
            throw "At least one of 'create', 'update', or 'delete' options must be true. Current settings: create=$createEnabled, update=$updateEnabled, delete=$deleteEnabled"
        }

        # dryRun from settings enables WhatIf if not already set via command line
        if ($settings.options.dryRun -eq $true -and -not $WhatIfPreference) {
            $script:WhatIfPreference = $true
        }

        # Set operation mode based on CUD option
        $RemoveExisting = $settings.options.delete -eq $true
        $Force = $settings.options.update -eq $true

        # testMode from settings - only imports first item of each type
        $TestMode = $settings.options.testMode -eq $true

        # verbose from settings enables verbose output
        if ($settings.options.verbose -eq $true) {
            $VerbosePreference = 'Continue'
        }
    }

    # Initialize logging (after applying verbose setting)
    $logsPath = Join-Path -Path $moduleRoot -ChildPath 'Logs'
    Initialize-HydrationLogging -LogPath $logsPath -EnableVerbose:($VerbosePreference -eq 'Continue')

    Write-HydrationLog -Message "=== Intune Hydration Kit Started ===" -Level Info
    Write-HydrationLog -Message "Loaded settings for tenant: $($settings.tenant.tenantId)" -Level Info

    if ($WhatIfPreference) {
        Write-HydrationLog -Message "Running in DRY-RUN mode - no changes will be made" -Level Warning
    }

    if ($Force) {
        Write-HydrationLog -Message "Force update enabled - existing configurations will be updated" -Level Info
    }

    if ($RemoveExisting) {
        if (-not $createEnabled) {
            Write-HydrationLog -Message "DELETE-ONLY mode - configurations will be deleted without recreation" -Level Warning
        }
        else {
            Write-HydrationLog -Message "Remove existing enabled - matching configurations will be deleted before import" -Level Warning
        }
    }

    if ($TestMode) {
        Write-HydrationLog -Message "Test mode enabled - only first item of each type will be imported" -Level Warning
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

    # Always connect to Graph API (needed for dry-run to check existing policies)
    Connect-IntuneHydration @authParams

    # Step 2: Pre-flight checks
    Write-HydrationLog -Message "Step 2: Running pre-flight checks" -Level Info

    # Always run pre-flight checks (read-only operations)
    Test-IntunePrerequisites | Out-Null

    # Step 3: Create Dynamic Groups
    if ($settings.imports.dynamicGroups) {
        Write-HydrationLog -Message "Step 3: Creating Dynamic Groups" -Level Info

        # Delete existing dynamic groups if RemoveExisting is set - ONLY groups defined in templates
        if ($RemoveExisting) {
            Write-HydrationLog -Message "Removing managed dynamic groups..." -Level Info

            # Get managed group names from templates
            $managedGroupNames = @()
            $groupsTemplatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups'
            if (Test-Path -Path $groupsTemplatePath) {
                $groupTemplates = Get-ChildItem -Path $groupsTemplatePath -Filter "*.json" -File
                foreach ($templateFile in $groupTemplates) {
                    $templateContent = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json
                    $groups = if ($templateContent.groups) { $templateContent.groups } else { @($templateContent) }
                    foreach ($groupDef in $groups) {
                        $managedGroupNames += $groupDef.displayName
                    }
                }
            }

            try {
                # Get all dynamic groups
                $existingGroups = Invoke-MgGraphRequest -Method GET -Uri "beta/groups?`$filter=groupTypes/any(c:c eq 'DynamicMembership')&`$select=id,displayName" -ErrorAction Stop
                foreach ($group in $existingGroups.value) {
                    # Only delete if it matches a managed group name
                    if ($group.displayName -notin $managedGroupNames) {
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($group.displayName, "Delete dynamic group")) {
                        try {
                            Invoke-MgGraphRequest -Method DELETE -Uri "beta/groups/$($group.id)" -ErrorAction Stop
                            Write-HydrationLog -Message "  Deleted: $($group.displayName)" -Level Info
                            $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $group.displayName -Action 'Deleted' -Status 'Success'
                        }
                        catch {
                            Write-HydrationLog -Message "Failed to delete group '$($group.displayName)': $_" -Level Warning
                            $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $group.displayName -Action 'Failed' -Status $_.Exception.Message
                        }
                    }
                    else {
                        $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $group.displayName -Action 'WouldDelete' -Status 'DryRun'
                    }
                }
            }
            catch {
                Write-HydrationLog -Message "Failed to list dynamic groups: $_" -Level Warning
            }
        }
        else {
            # Normal create mode
            $groupsTemplatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups'

            if (Test-Path -Path $groupsTemplatePath) {
                $groupTemplates = Get-ChildItem -Path $groupsTemplatePath -Filter "*.json" -File

                # Collect all groups from templates
                $allGroupDefs = @()
                foreach ($templateFile in $groupTemplates) {
                    $templateContent = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json

                    # Handle templates with multiple groups
                    $groups = if ($templateContent.groups) { $templateContent.groups } else { @($templateContent) }
                    $allGroupDefs += $groups
                }

                # Apply test mode - only process first item
                if ($TestMode -and $allGroupDefs.Count -gt 0) {
                    $allGroupDefs = @($allGroupDefs[0])
                }

                foreach ($groupDef in $allGroupDefs) {
                    if ($PSCmdlet.ShouldProcess($groupDef.displayName, "Create dynamic group")) {
                        $groupResult = New-IntuneDynamicGroup -DisplayName $groupDef.displayName -Description $groupDef.description -MembershipRule $groupDef.membershipRule

                        $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $groupDef.displayName -Action $groupResult.Action -Id $groupResult.Id -Details $groupResult.Reason
                        Write-HydrationLog -Message "  $($groupResult.Action): $($groupDef.displayName)" -Level Info
                    }
                }
            }
            else {
                Write-HydrationLog -Message "Dynamic Groups template directory not found" -Level Warning
            }
        }
    }

    # Step 4: Create Device Filters
    if ($settings.imports.deviceFilters) {
        Write-HydrationLog -Message "Step 4: Creating Device Filters" -Level Info

        # Import function handles ShouldProcess internally for each filter
        $filterResults = Import-IntuneDeviceFilter -Force:$Force -RemoveExisting:$RemoveExisting -TestMode:$TestMode -WhatIf:$WhatIfPreference
        $allResults += $filterResults
    }

    # Step 5: Import OpenIntuneBaseline
    if ($settings.imports.openIntuneBaseline) {
        Write-HydrationLog -Message "Step 5: Importing OpenIntuneBaseline policies" -Level Info

        $baselineParams = @{}

        if ($settings.openIntuneBaseline.downloadPath) {
            $baselineParams['BaselinePath'] = $settings.openIntuneBaseline.downloadPath
        }

        # Import function handles ShouldProcess internally for each policy
        $baselineParams['Force'] = $Force
        $baselineParams['RemoveExisting'] = $RemoveExisting
        $baselineParams['TestMode'] = $TestMode
        $baselineParams['WhatIf'] = $WhatIfPreference
        $baselineResults = Import-IntuneBaseline @baselineParams
        $allResults += $baselineResults
    }

    # Step 6: Import Compliance Templates (local)
    if ($settings.imports.complianceTemplates) {
        Write-HydrationLog -Message "Step 6: Importing Compliance templates" -Level Info

        # Import function handles ShouldProcess internally for each policy
        $complianceResults = Import-IntuneCompliancePolicy -Force:$Force -RemoveExisting:$RemoveExisting -TestMode:$TestMode -WhatIf:$WhatIfPreference
        $allResults += $complianceResults
    }

    # Step 7: Import Notification Templates
    if ($settings.imports.notificationTemplates) {
        Write-HydrationLog -Message "Step 7: Importing Notification Templates" -Level Info

        # Import function handles ShouldProcess internally for each template
        $notificationResults = Import-IntuneNotificationTemplate -Force:$Force -RemoveExisting:$RemoveExisting -TestMode:$TestMode -WhatIf:$WhatIfPreference
        $allResults += $notificationResults
    }

    # Step 8: Import App Protection Policies (MAM)
    if ($settings.imports.appProtection) {
        Write-HydrationLog -Message "Step 8: Importing App Protection policies" -Level Info

        # Import function handles ShouldProcess internally for each policy
        $mamResults = Import-IntuneAppProtectionPolicy -Force:$Force -RemoveExisting:$RemoveExisting -TestMode:$TestMode -WhatIf:$WhatIfPreference
        $allResults += $mamResults
    }

    # Step 9: Import Enrollment Profiles
    if ($settings.imports.enrollmentProfiles) {
        Write-HydrationLog -Message "Step 9: Importing Enrollment Profiles" -Level Info

        # Import function handles ShouldProcess internally for each profile
        $enrollmentResults = Import-IntuneEnrollmentProfile -Force:$Force -RemoveExisting:$RemoveExisting -TestMode:$TestMode -WhatIf:$WhatIfPreference
        $allResults += $enrollmentResults
    }

    # Step 10: Import Conditional Access Starter Pack
    if ($settings.imports.conditionalAccess) {
        Write-HydrationLog -Message "Step 10: Importing Conditional Access Starter Pack" -Level Info

        # Import function handles ShouldProcess internally for each policy
        $caResults = Import-IntuneConditionalAccessPolicy -Force:$Force -RemoveExisting:$RemoveExisting -TestMode:$TestMode -WhatIf:$WhatIfPreference
        $allResults += $caResults
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
| Total Operations | $($allResults.Count) |
| Created | $($summary.Created) |
| Updated | $($summary.Updated) |
| Skipped | $($summary.Skipped) |
| Would Create | $($summary.WouldCreate) |
| Would Update | $($summary.WouldUpdate) |
| Failed | $($summary.Failed) |

## Details by Type

"@

    # Group results by type
    $byType = $allResults | Group-Object -Property Type
    foreach ($typeGroup in $byType) {
        $typeResults = $typeGroup.Group
        $created = ($typeResults | Where-Object { $_.Action -eq 'Created' }).Count
        $updated = ($typeResults | Where-Object { $_.Action -eq 'Updated' }).Count
        $skipped = ($typeResults | Where-Object { $_.Action -eq 'Skipped' }).Count
        $wouldCreate = ($typeResults | Where-Object { $_.Action -eq 'WouldCreate' }).Count
        $failed = ($typeResults | Where-Object { $_.Action -eq 'Failed' }).Count

        $wouldUpdate = ($typeResults | Where-Object { $_.Action -eq 'WouldUpdate' }).Count

        $reportContent += @"

### $($typeGroup.Name)
- Created: $created
- Updated: $updated
- Skipped: $skipped
- Would Create: $wouldCreate
- Would Update: $wouldUpdate
- Failed: $failed

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
    Write-Host "" -InformationAction Continue
    Write-Host "---------------- Summary ----------------" -InformationAction Continue
    if ($WhatIfPreference) {
        Write-Host ("Would Create: {0} | Would Update: {1} | Would Delete: {2} | Skipped: {3} | Failed: {4}" -f $summary.WouldCreate, $summary.WouldUpdate, $summary.WouldDelete, $summary.Skipped, $summary.Failed) -InformationAction Continue
    }
    else {
        Write-Host ("Created: {0} | Updated: {1} | Deleted: {2} | Skipped: {3} | Failed: {4}" -f $summary.Created, $summary.Updated, $summary.Deleted, $summary.Skipped, $summary.Failed) -InformationAction Continue
    }
    Write-Host "Reports: $reportPath" -InformationAction Continue
    if ($jsonReportPath) {
        Write-Host "JSON:    $jsonReportPath" -InformationAction Continue
    }
    Write-Host "----------------------------------------" -InformationAction Continue

    # Exit with appropriate code
    if ($summary.Failed -gt 0) {
        Write-HydrationLog -Message "Completed with $($summary.Failed) failures" -Level Warning
        exit 1
    }
    else {
        if ($WhatIfPreference) {
            Write-HydrationLog -Message "Dry-run completed: $($summary.WouldCreate) would create, $($summary.WouldUpdate) would update, $($summary.WouldDelete) would delete, $($summary.Skipped) skipped" -Level Info
        }
        else {
            Write-HydrationLog -Message "Completed successfully: $($summary.Created) created, $($summary.Updated) updated, $($summary.Skipped) skipped" -Level Info
        }
        exit 0
    }
}
catch {
    Write-HydrationLog -Message "Fatal error: $_" -Level Error
    Write-Error $_
    exit 1
}

#endregion
