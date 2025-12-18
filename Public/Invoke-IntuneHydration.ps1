#Requires -Version 7.0

function Invoke-IntuneHydration {
    <#
    .SYNOPSIS
        Main orchestrator function for Intune tenant hydration
    .DESCRIPTION
        Executes the complete hydration workflow including authentication,
        pre-flight checks, and import of all baseline configurations.

        Two mutually exclusive invocation modes:
        1. Settings File Mode: Use -SettingsPath to load all configuration from a JSON file
        2. Parameter Mode: Use -Interactive or -ClientId/-ClientSecret with other parameters

        These modes cannot be mixed - choose one or the other.
    .PARAMETER SettingsPath
        Path to the settings JSON file. Use this for settings file-based invocation.
        Cannot be combined with -Interactive, -ClientId, or -ClientSecret.
    .PARAMETER TenantId
        Azure AD tenant ID (GUID). Required for parameter-based invocation.
    .PARAMETER TenantName
        Tenant name for display purposes (e.g., contoso.onmicrosoft.com)
    .PARAMETER Interactive
        Use interactive authentication (browser-based login).
        Cannot be combined with -SettingsPath.
    .PARAMETER ClientId
        Application (client) ID for service principal authentication.
        Cannot be combined with -SettingsPath.
    .PARAMETER ClientSecret
        Client secret for service principal authentication (SecureString).
        Cannot be combined with -SettingsPath.
    .PARAMETER Environment
        Azure cloud environment. Valid values: Global, USGov, USGovDoD, Germany, China
    .PARAMETER Create
        Enable creation of configurations
    .PARAMETER Delete
        Enable deletion of kit-created configurations
    .PARAMETER Force
        Skip confirmation prompt when running in delete mode (available for both settings-file and parameter modes)
    .PARAMETER VerboseOutput
        Enable verbose logging output
    .PARAMETER OpenIntuneBaseline
        Process OpenIntuneBaseline policies
    .PARAMETER ComplianceTemplates
        Process compliance policy templates
    .PARAMETER AppProtection
        Process app protection policies
    .PARAMETER NotificationTemplates
        Process notification templates
    .PARAMETER EnrollmentProfiles
        Process enrollment profiles (Autopilot, ESP)
    .PARAMETER DynamicGroups
        Process dynamic groups
    .PARAMETER StaticGroups
        Process static (assigned) groups
    .PARAMETER DeviceFilters
        Process device filters
    .PARAMETER ConditionalAccess
        Process Conditional Access starter pack policies
    .PARAMETER MobileApps
        Process mobile app templates
    .PARAMETER All
        Enable all targets
    .PARAMETER BaselineRepoUrl
        GitHub repository URL for OpenIntuneBaseline
    .PARAMETER BaselineBranch
        Git branch to use for OpenIntuneBaseline
    .PARAMETER BaselineDownloadPath
        Local path for OpenIntuneBaseline download
    .PARAMETER ReportOutputPath
        Output directory for reports
    .PARAMETER ReportFormats
        Report formats to generate (markdown, json)
    .EXAMPLE
        Invoke-IntuneHydration -SettingsPath ./settings.json

        Run using settings from a JSON file.
    .EXAMPLE
        Invoke-IntuneHydration -SettingsPath ./settings.json -WhatIf

        Dry-run using settings file.
    .EXAMPLE
        Invoke-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive -Create -All

        Run with all imports enabled using interactive authentication.
    .EXAMPLE
        Invoke-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -ClientId "client-id" -ClientSecret $secret -Create -ComplianceTemplates -DynamicGroups

        Run with service principal authentication and specific imports enabled.
    .EXAMPLE
        Invoke-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive -Delete -All -WhatIf

        Dry-run delete mode with interactive authentication.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'SettingsFile')]
    param(
        # Settings file parameter - exclusive mode
        [Parameter(ParameterSetName = 'SettingsFile', Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path $_ })]
        [string]$SettingsPath,

        # Tenant parameters - required for parameter-based modes
        [Parameter(ParameterSetName = 'Interactive', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [string]$TenantName,

        # Authentication parameters - Interactive mode
        [Parameter(ParameterSetName = 'Interactive', Mandatory = $true)]
        [switch]$Interactive,

        # Authentication parameters - Service Principal mode
        [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $true)]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $true)]
        [SecureString]$ClientSecret,

        # Environment - available for parameter-based modes only
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'Germany', 'China')]
        [string]$Environment = 'Global',

        # Options parameters - available for parameter-based modes only
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$Create,

        [Parameter(ParameterSetName = 'SettingsFile')]
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$Delete,

        [Parameter(ParameterSetName = 'SettingsFile')]
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$VerboseOutput,

        # Target enable switches - available for parameter-based modes only
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$OpenIntuneBaseline,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$ComplianceTemplates,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$AppProtection,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$NotificationTemplates,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$EnrollmentProfiles,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$DynamicGroups,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$StaticGroups,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$DeviceFilters,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$ConditionalAccess,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$MobileApps,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$All,

        # OpenIntuneBaseline parameters - available for parameter-based modes only
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [string]$BaselineRepoUrl = "https://github.com/SkipToTheEndpoint/OpenIntuneBaseline",

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [string]$BaselineBranch = 'main',

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [string]$BaselineDownloadPath,

        # Reporting parameters - available for parameter-based modes only
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [string]$ReportOutputPath,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [ValidateSet('markdown', 'json')]
        [string[]]$ReportFormats
    )

    $ErrorActionPreference = 'Stop'
    $InformationPreference = 'Continue'

    # Resolve module root - use $script:ModuleRoot if set by psm1, otherwise use PSScriptRoot parent
    $moduleRoot = if ($script:ModuleRoot) {
        $script:ModuleRoot
    } else {
        Split-Path -Path $PSScriptRoot -Parent
    }

    #region Main Execution

    try {
        # Initialize settings based on parameter set
        $settings = $null

        if ($PSCmdlet.ParameterSetName -eq 'SettingsFile') {
            # Settings file mode - load everything from the file
            $settings = Import-HydrationSettings -Path $SettingsPath
            Write-Host "Loaded settings from: $SettingsPath" -InformationAction Continue
            if (-not $settings.options) {
                $settings['options'] = @{}
            }
            # Set force option from parameter, preserving any existing force setting from settings file
            $settings.options.force = $Force.IsPresent -or ($settings.options.ContainsKey('force') -and $settings.options.force)
        } else {
            # Parameter-based mode - build settings from parameters
            Write-Host "Using parameter-based configuration" -InformationAction Continue

            # Determine which targets are enabled
            $importsEnabled = @{
                dynamicGroups         = $All.IsPresent -or $DynamicGroups.IsPresent
                staticGroups          = $All.IsPresent -or $StaticGroups.IsPresent
                deviceFilters         = $All.IsPresent -or $DeviceFilters.IsPresent
                conditionalAccess     = $All.IsPresent -or $ConditionalAccess.IsPresent
                complianceTemplates   = $All.IsPresent -or $ComplianceTemplates.IsPresent
                openIntuneBaseline    = $All.IsPresent -or $OpenIntuneBaseline.IsPresent
                enrollmentProfiles    = $All.IsPresent -or $EnrollmentProfiles.IsPresent
                appProtection         = $All.IsPresent -or $AppProtection.IsPresent
                notificationTemplates = $All.IsPresent -or $NotificationTemplates.IsPresent
                mobileApps            = $All.IsPresent -or $MobileApps.IsPresent
            }

            # Validate that at least one target is enabled
            if (-not ($importsEnabled.Values -contains $true)) {
                throw "At least one target must be enabled. Use -All or specify a target switch (e.g., -DynamicGroups, -DeviceFilters, etc.)."
            }

            # Build settings object from parameters
            $settings = @{
                tenant             = @{
                    tenantId   = $TenantId
                    tenantName = $TenantName
                }
                authentication     = @{
                    mode         = if ($Interactive) { 'interactive' } else { 'clientSecret' }
                    clientId     = $ClientId
                    clientSecret = if ($ClientSecret) { [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)) } else { $null }
                    environment  = $Environment
                }
                options            = @{
                    create  = $Create.IsPresent
                    delete  = $Delete.IsPresent
                    force   = $Force.IsPresent
                    dryRun  = [bool]$WhatIfPreference
                    verbose = $VerboseOutput.IsPresent
                }
                imports            = $importsEnabled
                openIntuneBaseline = @{
                    repoUrl      = $BaselineRepoUrl
                    branch       = $BaselineBranch
                    downloadPath = if ($BaselineDownloadPath) { $BaselineDownloadPath } else { './OpenIntuneBaseline' }
                }
                reporting          = @{
                    outputPath = if ($ReportOutputPath) { $ReportOutputPath } else { $null }
                    formats    = if ($ReportFormats) { $ReportFormats } else { @('markdown') }
                }
            }
        }

        # Display current settings
        Write-Host "Target Tenant: $($settings.tenant.tenantId)" -InformationAction Continue
        if ($settings.tenant.tenantName) {
            Write-Host "Tenant Name: $($settings.tenant.tenantName)" -InformationAction Continue
        }
        Write-Host "Authentication Mode: $($settings.authentication.mode)" -InformationAction Continue
        Write-Host "Options:" -InformationAction Continue
        Write-Host ($settings.options | Out-String) -InformationAction Continue
        Write-Host "Imports Enabled:" -InformationAction Continue
        Write-Host ($settings.imports | Out-String) -InformationAction Continue

        # Apply options from settings
        $createEnabled = $settings.options.create -eq $true
        $deleteEnabled = $settings.options.delete -eq $true
        $forceDelete = $settings.options.force -eq $true
        $RemoveExisting = $deleteEnabled

        # Validate options - create and delete are mutually exclusive
        if ($createEnabled -and $deleteEnabled) {
            throw "Only one of 'create' or 'delete' options can be true. Current settings: create=$createEnabled, delete=$deleteEnabled"
        }

        if (-not $createEnabled -and -not $deleteEnabled) {
            throw "At least one of 'create' or 'delete' options must be true. Current settings: create=$createEnabled, delete=$deleteEnabled"
        }

        if ($deleteEnabled -and -not $forceDelete -and -not $WhatIfPreference) {
            if (-not $PSCmdlet.ShouldContinue("Proceed with delete operations?", "Delete mode will remove Intune configurations created by the hydration kit.")) {
                Write-Warning "Delete operation cancelled by user confirmation."
                return
            }
        }

        # dryRun from settings enables WhatIf if not already set via command line
        if ($settings.options.dryRun -eq $true -and -not $WhatIfPreference) {
            $script:WhatIfPreference = $true
        }

        # verbose from settings enables verbose output
        if ($settings.options.verbose -eq $true) {
            $script:VerbosePreference = 'Continue'
        }

        # Initialize logging (after applying verbose setting)
        # Uses OS temp directory by default (e.g., $env:TEMP/IntuneHydrationKit/Logs on Windows, /tmp/IntuneHydrationKit/Logs on macOS/Linux)
        Initialize-HydrationLogging -EnableVerbose:($VerbosePreference -eq 'Continue')

        Write-HydrationLog -Message "=== Intune Hydration Kit Started ===" -Level Info
        Write-HydrationLog -Message "Loaded settings for tenant: $(Get-ObfuscatedTenantId -TenantId $settings.tenant.tenantId)" -Level Info

        if ($WhatIfPreference) {
            Write-HydrationLog -Message "Running in DRY-RUN mode - no changes will be made" -Level Warning
        }

        if ($RemoveExisting) {
            if (-not $createEnabled) {
                Write-HydrationLog -Message "DELETE-ONLY mode - configurations will be deleted without recreation" -Level Warning
            } else {
                Write-HydrationLog -Message "Remove existing enabled - matching configurations will be deleted before import" -Level Warning
            }
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

        if ($settings.authentication.mode -eq 'clientSecret') {
            $authParams['ClientId'] = $settings.authentication.clientId
            $authParams['ClientSecret'] = $settings.authentication.clientSecret | ConvertTo-SecureString -AsPlainText -Force
        } else {
            $authParams['Interactive'] = $true
        }

        # Always connect to Graph API (needed for dry-run to check existing policies)
        Connect-IntuneHydration @authParams

        # Step 2: Pre-flight checks
        Write-HydrationLog -Message "Step 2: Running pre-flight checks" -Level Info

        # Always run pre-flight checks (read-only operations)
        Test-IntunePrerequisites | Out-Null

        # Step 3: Dynamic Groups
        if ($settings.imports.dynamicGroups) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Creating" }
            Write-HydrationLog -Message "Step 3: $stepAction Dynamic Groups" -Level Info

            # Delete existing dynamic groups if RemoveExisting is set
            # SAFETY: Only delete groups that have "Imported by Intune-Hydration-Kit" in description
            if ($RemoveExisting) {

                try {
                    # Get all dynamic groups with descriptions
                    $listUri = "beta/groups?`$filter=groupTypes/any(c:c eq 'DynamicMembership')&`$select=id,displayName,description"
                    do {
                        $existingGroups = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                        foreach ($group in $existingGroups.value) {
                            # Safety check: Only delete if created by this kit (has hydration marker in description)
                            if (-not (Test-HydrationKitObject -Description $group.description -ObjectName $group.displayName)) {
                                Write-Verbose "Skipping '$($group.displayName)' - not created by Intune-Hydration-Kit"
                                continue
                            }

                            if ($PSCmdlet.ShouldProcess($group.displayName, "Delete dynamic group")) {
                                try {
                                    Invoke-MgGraphRequest -Method DELETE -Uri "beta/groups/$($group.id)" -ErrorAction Stop
                                    Write-HydrationLog -Message "  Deleted: $($group.displayName)" -Level Info
                                    $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $group.displayName -Action 'Deleted' -Status 'Success'
                                } catch {
                                    Write-HydrationLog -Message "Failed to delete group '$($group.displayName)': $_" -Level Warning
                                    $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $group.displayName -Action 'Failed' -Status $_.Exception.Message
                                }
                            } else {
                                $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $group.displayName -Action 'WouldDelete' -Status 'DryRun'
                            }
                        }
                        $listUri = $existingGroups.'@odata.nextLink'
                    } while ($listUri)
                } catch {
                    Write-HydrationLog -Message "Failed to list dynamic groups: $_" -Level Warning
                }
            } else {
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

                    foreach ($groupDef in $allGroupDefs) {
                        if ($PSCmdlet.ShouldProcess($groupDef.displayName, "Create dynamic group")) {
                            $groupResult = New-IntuneDynamicGroup -DisplayName $groupDef.displayName -Description $groupDef.description -MembershipRule $groupDef.membershipRule

                            $allResults += New-HydrationResult -Type 'DynamicGroup' -Name $groupDef.displayName -Action $groupResult.Action -Id $groupResult.Id -Details $groupResult.Reason
                            Write-HydrationLog -Message "  $($groupResult.Action): $($groupDef.displayName)" -Level Info
                        }
                    }
                } else {
                    Write-HydrationLog -Message "Dynamic Groups template directory not found" -Level Warning
                }
            }
        }

        # Step 3b: Static Groups
        if ($settings.imports.staticGroups) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Creating" }
            Write-HydrationLog -Message "Step 3b: $stepAction Static Groups" -Level Info

            # Delete existing static groups if RemoveExisting is set
            # SAFETY: Only delete groups that have "Imported by Intune-Hydration-Kit" in description
            if ($RemoveExisting) {
                try {
                    # Get all security groups (non-dynamic) with hydration kit marker in description
                    # Note: Using ConsistencyLevel header and $count for advanced query with NOT operator
                    $listUri = "beta/groups?`$filter=securityEnabled eq true and NOT groupTypes/any(c:c eq 'DynamicMembership')&`$select=id,displayName,description&`$count=true"
                    $headers = @{ 'ConsistencyLevel' = 'eventual' }
                    do {
                        $existingGroups = Invoke-MgGraphRequest -Method GET -Uri $listUri -Headers $headers -ErrorAction Stop
                        foreach ($group in $existingGroups.value) {
                            # Safety check: Only delete if created by this kit (has hydration marker in description)
                            if (-not (Test-HydrationKitObject -Description $group.description -ObjectName $group.displayName)) {
                                Write-Verbose "Skipping '$($group.displayName)' - not created by Intune-Hydration-Kit"
                                continue
                            }

                            if ($PSCmdlet.ShouldProcess($group.displayName, "Delete static group")) {
                                try {
                                    Invoke-MgGraphRequest -Method DELETE -Uri "beta/groups/$($group.id)" -ErrorAction Stop
                                    Write-HydrationLog -Message "  Deleted: $($group.displayName)" -Level Info
                                    $allResults += New-HydrationResult -Type 'StaticGroup' -Name $group.displayName -Action 'Deleted' -Status 'Success'
                                } catch {
                                    Write-HydrationLog -Message "Failed to delete group '$($group.displayName)': $_" -Level Warning
                                    $allResults += New-HydrationResult -Type 'StaticGroup' -Name $group.displayName -Action 'Failed' -Status $_.Exception.Message
                                }
                            } else {
                                $allResults += New-HydrationResult -Type 'StaticGroup' -Name $group.displayName -Action 'WouldDelete' -Status 'DryRun'
                            }
                        }
                        $listUri = $existingGroups.'@odata.nextLink'
                    } while ($listUri)
                } catch {
                    Write-HydrationLog -Message "Failed to list static groups: $_" -Level Warning
                }
            } else {
                # Normal create mode
                $staticGroupsTemplatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/StaticGroups'

                if (Test-Path -Path $staticGroupsTemplatePath) {
                    $groupTemplates = Get-ChildItem -Path $staticGroupsTemplatePath -Filter "*.json" -File

                    # Collect all groups from templates
                    $allGroupDefs = @()
                    foreach ($templateFile in $groupTemplates) {
                        $templateContent = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json

                        # Handle templates with multiple groups
                        $groups = if ($templateContent.groups) { $templateContent.groups } else { @($templateContent) }
                        $allGroupDefs += $groups
                    }

                    foreach ($groupDef in $allGroupDefs) {
                        if ($PSCmdlet.ShouldProcess($groupDef.displayName, "Create static group")) {
                            $groupResult = New-IntuneStaticGroup -DisplayName $groupDef.displayName -Description $groupDef.description

                            $allResults += New-HydrationResult -Type 'StaticGroup' -Name $groupDef.displayName -Action $groupResult.Action -Id $groupResult.Id -Details $groupResult.Reason
                            Write-HydrationLog -Message "  $($groupResult.Action): $($groupDef.displayName)" -Level Info
                        }
                    }
                } else {
                    Write-HydrationLog -Message "Static Groups template directory not found" -Level Warning
                }
            }
        }

        # Step 4: Device Filters
        if ($settings.imports.deviceFilters) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Creating" }
            Write-HydrationLog -Message "Step 4: $stepAction Device Filters" -Level Info

            $filterResults = Import-IntuneDeviceFilter -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $filterResults
        }

        # Step 5: OpenIntuneBaseline
        if ($settings.imports.openIntuneBaseline) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 5: $stepAction OpenIntuneBaseline policies" -Level Info

            $baselineParams = @{}

            if ($settings.openIntuneBaseline.downloadPath) {
                $baselineParams['BaselinePath'] = $settings.openIntuneBaseline.downloadPath
            }

            # Import function handles ShouldProcess internally for each policy
            $baselineParams['RemoveExisting'] = $RemoveExisting
            $baselineParams['WhatIf'] = $WhatIfPreference
            $baselineResults = Import-IntuneBaseline @baselineParams
            $allResults += $baselineResults
        }

        # Step 6: Compliance Templates
        if ($settings.imports.complianceTemplates) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 6: $stepAction Compliance templates" -Level Info

            $complianceResults = Import-IntuneCompliancePolicy -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $complianceResults
        }

        # Step 7: Notification Templates
        if ($settings.imports.notificationTemplates) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 7: $stepAction Notification Templates" -Level Info

            $notificationResults = Import-IntuneNotificationTemplate -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $notificationResults
        }

        # Step 8: App Protection Policies (MAM)
        if ($settings.imports.appProtection) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 8: $stepAction App Protection policies" -Level Info

            $mamResults = Import-IntuneAppProtectionPolicy -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $mamResults
        }

        # Step 9: Enrollment Profiles
        if ($settings.imports.enrollmentProfiles) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 9: $stepAction Enrollment Profiles" -Level Info

            $enrollmentResults = Import-IntuneEnrollmentProfile -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $enrollmentResults
        }

        # Step 10: Conditional Access Starter Pack
        if ($settings.imports.conditionalAccess) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 10: $stepAction Conditional Access Starter Pack" -Level Info

            $caResults = Import-IntuneConditionalAccessPolicy -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $caResults
        }

        # Step 11: Mobile Apps
        if ($settings.imports.mobileApps) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 11: $stepAction Mobile Apps" -Level Info

            $mobileAppResults = Import-IntuneMobileApp -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $mobileAppResults
        }

        # Step 12: Generate Summary Report
        Write-HydrationLog -Message "Step 12: Generating Summary Report" -Level Info

        # Use OS temp directory for reports if no explicit path provided
        if ($settings.reporting.outputPath) {
            $reportsPath = $settings.reporting.outputPath
        } else {
            $tempBase = [System.IO.Path]::GetTempPath()
            $reportsPath = Join-Path -Path $tempBase -ChildPath 'IntuneHydrationKit/Reports'
        }
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
                $reportContent += "| $($result.Timestamp) | $($result.Type) | $($result.Name) | $($result.Action) | $($result.Id) | $($result.Status) |`n"
            }
        }

        $reportContent += @"

## Important Notes

- **Conditional Access policies** were created in **DISABLED** state. Review and enable as needed.
- **OpenIntuneBaseline policies** were imported using IntuneManagement module.
- Review all configurations before enabling in production.

"@

        $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
        Write-HydrationLog -Message "Summary report written to: $reportPath" -Level Info

        # Also write JSON if requested
        if ('json' -in $settings.reporting.formats) {
            $jsonReportPath = Join-Path -Path $reportsPath -ChildPath "Hydration-Summary.json"
            @{
                Timestamp   = $timestamp
                Tenant      = $settings.tenant.tenantId
                Environment = $settings.authentication.environment
                Mode        = if ($WhatIfPreference) { 'DryRun' } else { 'Live' }
                Summary     = $summary
                Results     = $allResults
            } | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReportPath -Encoding UTF8
            Write-HydrationLog -Message "JSON report written to: $jsonReportPath" -Level Info
        }

        Write-HydrationLog -Message "=== Intune Hydration Kit Completed ===" -Level Info

        # Friendly console summary
        Write-Host "" -InformationAction Continue
        Write-Host "---------------- Summary ----------------" -InformationAction Continue
        if ($WhatIfPreference) {
            Write-Host ("Would Create: {0} | Would Update: {1} | Would Delete: {2} | Skipped: {3} | Failed: {4}" -f $summary.WouldCreate, $summary.WouldUpdate, $summary.WouldDelete, $summary.Skipped, $summary.Failed) -InformationAction Continue
        } else {
            Write-Host ("Created: {0} | Updated: {1} | Deleted: {2} | Skipped: {3} | Failed: {4}" -f $summary.Created, $summary.Updated, $summary.Deleted, $summary.Skipped, $summary.Failed) -InformationAction Continue
        }
        Write-Host "Reports: $reportPath" -InformationAction Continue
        if ($jsonReportPath) {
            Write-Host "JSON:    $jsonReportPath" -InformationAction Continue
        }
        Write-Host "----------------------------------------" -InformationAction Continue

        # Return summary object instead of exiting (functions shouldn't call exit)
        if ($summary.Failed -gt 0) {
            Write-HydrationLog -Message "Completed with $($summary.Failed) failures" -Level Warning
            return @{
                Success = $false
                Summary = $summary
                Results = $allResults
                ReportPath = $reportPath
                JsonReportPath = $jsonReportPath
            }
        } else {
            if ($WhatIfPreference) {
                Write-HydrationLog -Message "Dry-run completed: $($summary.WouldCreate) would create, $($summary.WouldUpdate) would update, $($summary.WouldDelete) would delete, $($summary.Skipped) skipped" -Level Info
            } else {
                Write-HydrationLog -Message "Completed successfully: $($summary.Created) created, $($summary.Updated) updated, $($summary.Deleted) deleted, $($summary.Skipped) skipped" -Level Info
            }
            return @{
                Success = $true
                Summary = $summary
                Results = $allResults
                ReportPath = $reportPath
                JsonReportPath = $jsonReportPath
            }
        }
    } catch {
        Write-HydrationLog -Message "Fatal error: $_" -Level Error
        throw
    }

    #endregion
}
