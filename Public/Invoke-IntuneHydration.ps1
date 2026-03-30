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
        Azure AD tenant ID (GUID format). Required for parameter-based invocation.
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
    .PARAMETER Platform
        Filter imports by platform. Valid values: Windows, macOS, iOS, Android, Linux, All.
        Defaults to 'All' which imports resources for all platforms.
        This affects: ComplianceTemplates, DeviceFilters, AppProtection, MobileApps, EnrollmentProfiles, OpenIntuneBaseline.
        Cross-platform resources (DynamicGroups, StaticGroups, ConditionalAccess, NotificationTemplates) are not filtered.
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

        # Platform filter - available for all parameter sets
        [Parameter(ParameterSetName = 'SettingsFile')]
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')]
        [string[]]$Platform = @('All'),

        # OpenIntuneBaseline parameters - available for parameter-based modes only
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [string]$BaselineRepoUrl = "https://github.com/jorgeasaurus/OpenIntuneBaseline",

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

            # Set platforms - command-line parameter takes precedence over settings file
            if ($Platform -and $Platform -notcontains 'All') {
                $settings['platforms'] = $Platform
            } elseif (-not $settings.platforms) {
                $settings['platforms'] = @('All')
            }
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
                platforms          = if ($Platform) { $Platform } else { @('All') }
            }
        }

        # Display current settings
        Write-Host "Target Tenant: $(Get-ObfuscatedTenantId -TenantId $settings.tenant.tenantId)" -InformationAction Continue
        if ($settings.tenant.tenantName) {
            Write-Host "Tenant Name: $($settings.tenant.tenantName)" -InformationAction Continue
        }
        Write-Host "Authentication Mode: $($settings.authentication.mode)" -InformationAction Continue
        Write-Host "Options:" -InformationAction Continue
        Write-Host ($settings.options | Out-String) -InformationAction Continue
        Write-Host "Imports Enabled:" -InformationAction Continue
        Write-Host ($settings.imports | Out-String) -InformationAction Continue
        Write-Host "Platform Filter: $($settings.platforms -join ', ')" -InformationAction Continue

        # Build filtered platform lists for each import function based on what they support
        # Helper function to filter platforms by valid set
        function Get-ValidPlatforms {
            param([string[]]$ValidSet)
            if ($settings.platforms -contains 'All') { return @('All') }
            $valid = $settings.platforms | Where-Object { $_ -in $ValidSet }
            if ($valid.Count -eq 0) { return @('All') }
            return $valid
        }

        # Helper function to load group definitions from template directory
        function Get-GroupDefinitionsFromTemplates {
            param(
                [string]$TemplatePath,
                [string[]]$Platforms
            )
            if (-not (Test-Path -Path $TemplatePath)) {
                return $null
            }

            $allGroupDefs = @()
            $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File
            foreach ($templateFile in $templateFiles) {
                $content = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json
                $groups = if ($content.groups) { $content.groups } else { @($content) }
                $allGroupDefs += $groups
            }

            # Filter by platform
            $filtered = $allGroupDefs | Where-Object {
                $platform = if ($_.platform) { $_.platform } else { 'All' }
                ($Platforms -contains 'All') -or ($platform -eq 'All') -or ($platform -in $Platforms)
            }

            return @{
                All      = $allGroupDefs
                Filtered = @($filtered)
            }
        }

        $platformFilters = @{
            Compliance         = Get-ValidPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android', 'Linux')
            DeviceFilters      = Get-ValidPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android')
            AppProtection      = Get-ValidPlatforms -ValidSet @('iOS', 'Android')
            MobileApps         = Get-ValidPlatforms -ValidSet @('Windows', 'macOS')
            EnrollmentProfiles = Get-ValidPlatforms -ValidSet @('Windows', 'macOS')
            Baseline           = Get-ValidPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android')
            Groups             = Get-ValidPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android')
        }

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

            if ($RemoveExisting) {
                $deleteResults = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -WhatIf:$WhatIfPreference
                $allResults += $deleteResults
                foreach ($result in $deleteResults) {
                    if ($result.Name) {
                        Write-HydrationLog -Message "  $($result.Action): $($result.Name)" -Level Info
                    }
                }
            } else {
                $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups'
                $groupData = Get-GroupDefinitionsFromTemplates -TemplatePath $templatePath -Platforms $platformFilters.Groups

                if ($null -eq $groupData) {
                    Write-HydrationLog -Message "Dynamic Groups template directory not found" -Level Warning
                } else {
                    if ($groupData.Filtered.Count -lt $groupData.All.Count) {
                        Write-HydrationLog -Message "  Filtered to $($groupData.Filtered.Count) of $($groupData.All.Count) groups based on platform selection: $($platformFilters.Groups -join ', ')" -Level Info
                    }

                    $groupResults = Invoke-GroupBatchImport -GroupDefinitions $groupData.Filtered -GroupType 'Dynamic' -WhatIf:$WhatIfPreference
                    $allResults += $groupResults
                    foreach ($result in $groupResults) {
                        if ($result.Name) {
                            Write-HydrationLog -Message "  $($result.Action): $($result.Name)" -Level Info
                        }
                    }
                }
            }
        }

        # Step 3b: Static Groups
        if ($settings.imports.staticGroups) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Creating" }
            Write-HydrationLog -Message "Step 3b: $stepAction Static Groups" -Level Info

            if ($RemoveExisting) {
                $deleteResults = Invoke-GroupBatchImport -GroupType 'Static' -Delete -WhatIf:$WhatIfPreference
                $allResults += $deleteResults
                foreach ($result in $deleteResults) {
                    if ($result.Name) {
                        Write-HydrationLog -Message "  $($result.Action): $($result.Name)" -Level Info
                    }
                }
            } else {
                $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/StaticGroups'
                $groupData = Get-GroupDefinitionsFromTemplates -TemplatePath $templatePath -Platforms $platformFilters.Groups

                if ($null -eq $groupData) {
                    Write-HydrationLog -Message "Static Groups template directory not found" -Level Warning
                } else {
                    if ($groupData.Filtered.Count -lt $groupData.All.Count) {
                        Write-HydrationLog -Message "  Filtered to $($groupData.Filtered.Count) of $($groupData.All.Count) groups based on platform selection: $($platformFilters.Groups -join ', ')" -Level Info
                    }

                    $groupResults = Invoke-GroupBatchImport -GroupDefinitions $groupData.Filtered -GroupType 'Static' -WhatIf:$WhatIfPreference
                    $allResults += $groupResults
                    foreach ($result in $groupResults) {
                        if ($result.Name) {
                            Write-HydrationLog -Message "  $($result.Action): $($result.Name)" -Level Info
                        }
                    }
                }
            }
        }

        # Step 4: Device Filters
        if ($settings.imports.deviceFilters) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Creating" }
            Write-HydrationLog -Message "Step 4: $stepAction Device Filters" -Level Info

            $filterResults = Import-IntuneDeviceFilter -Platform $platformFilters.DeviceFilters -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
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
            $baselineParams['Platform'] = $platformFilters.Baseline
            $baselineResults = Import-IntuneBaseline @baselineParams
            $allResults += $baselineResults
        }

        # Step 6: Compliance Templates
        if ($settings.imports.complianceTemplates) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 6: $stepAction Compliance templates" -Level Info

            $complianceResults = Import-IntuneCompliancePolicy -Platform $platformFilters.Compliance -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
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

            $mamResults = Import-IntuneAppProtectionPolicy -Platform $platformFilters.AppProtection -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
            $allResults += $mamResults
        }

        # Step 9: Enrollment Profiles
        if ($settings.imports.enrollmentProfiles) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            Write-HydrationLog -Message "Step 9: $stepAction Enrollment Profiles" -Level Info

            $enrollmentResults = Import-IntuneEnrollmentProfile -Platform $platformFilters.EnrollmentProfiles -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
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

            $mobileAppResults = Import-IntuneMobileApp -Platform $platformFilters.MobileApps -RemoveExisting:$RemoveExisting -WhatIf:$WhatIfPreference
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
            # Always create reports directory regardless of -WhatIf (reports are observational, not tenant changes)
            New-Item -Path $reportsPath -ItemType Directory -Force -WhatIf:$false | Out-Null
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

            # Build table rows separately to avoid header/row formatting issues
            # Filter out results that don't have a Name or Action (invalid/empty results)
            $operationLines = foreach ($result in $allResults) {
                # Skip results with no meaningful data
                if (-not $result.Name -and -not $result.Action) {
                    continue
                }

                $timestamp = if ($result.Timestamp) { $result.Timestamp } else { '' }
                $type = if ($result.PSObject.Properties['Type']) { $result.Type } else { '' }
                $name = if ($result.Name) { $result.Name } else { '' }
                $action = if ($result.Action) { $result.Action } else { '' }
                $id = if ($result.PSObject.Properties['Id']) { $result.Id } else { '' }
                $status = if ($result.Status) { $result.Status } else { '' }

                "| {0} | {1} | {2} | {3} | {4} | {5} |" -f $timestamp, $type, $name, $action, $id, $status
            }

            # Explicit newline between header and first row to keep the table rendering clean
            $reportContent += "`n"
            $reportContent += ($operationLines -join "`n")
            $reportContent += "`n"
        }

        $reportContent += @"

## Important Notes

- **Conditional Access policies** were created in **DISABLED** state. Review and enable as needed.
- Review all configurations before enabling in production.

"@

        # Always write reports regardless of -WhatIf (reports are observational, not tenant changes)
        $reportContent | Out-File -FilePath $reportPath -Encoding UTF8 -WhatIf:$false
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
            } | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReportPath -Encoding UTF8 -WhatIf:$false
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

        # Log completion status
        if ($summary.Failed -gt 0) {
            Write-HydrationLog -Message "Completed with $($summary.Failed) failures" -Level Warning
        } elseif ($WhatIfPreference) {
            Write-HydrationLog -Message "Dry-run completed: $($summary.WouldCreate) would create, $($summary.WouldUpdate) would update, $($summary.WouldDelete) would delete, $($summary.Skipped) skipped" -Level Info
        } else {
            Write-HydrationLog -Message "Completed successfully: $($summary.Created) created, $($summary.Updated) updated, $($summary.Deleted) deleted, $($summary.Skipped) skipped" -Level Info
        }

        # Return summary object (functions shouldn't call exit)
        return @{
            Success        = $summary.Failed -eq 0
            Summary        = $summary
            Results        = $allResults
            ReportPath     = $reportPath
            JsonReportPath = $jsonReportPath
        }
    } catch {
        Write-HydrationLog -Message "Fatal error: $_" -Level Error
        throw
    }

    #endregion
}
