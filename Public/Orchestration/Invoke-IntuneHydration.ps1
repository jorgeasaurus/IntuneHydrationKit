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
        [switch]$CISBaselines,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [switch]$All,

        # Platform filter - available for all parameter sets
        [Parameter(ParameterSetName = 'SettingsFile')]
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'ServicePrincipal')]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')]
        [string[]]$Platform = @('All'),

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

    # Resolve module root - use $script:ModuleRoot if set by psm1, otherwise walk up two levels
    # from Public/Orchestration/ to the repo root
    $moduleRoot = if ($script:ModuleRoot) {
        $script:ModuleRoot
    } else {
        Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    }

    #region Main Execution

    $executionStartTime = Get-Date

    try {
        $resolveSettingsParams = @{
            ParameterSetName      = $PSCmdlet.ParameterSetName
            SettingsPath          = $SettingsPath
            Force                 = $Force
            Platform              = $Platform
            TenantId              = $TenantId
            TenantName            = $TenantName
            Interactive           = $Interactive
            ClientId              = $ClientId
            ClientSecret          = $ClientSecret
            Environment           = $Environment
            Create                = $Create
            Delete                = $Delete
            OpenIntuneBaseline    = $OpenIntuneBaseline
            ComplianceTemplates   = $ComplianceTemplates
            AppProtection         = $AppProtection
            NotificationTemplates = $NotificationTemplates
            EnrollmentProfiles    = $EnrollmentProfiles
            DynamicGroups         = $DynamicGroups
            StaticGroups          = $StaticGroups
            DeviceFilters         = $DeviceFilters
            ConditionalAccess     = $ConditionalAccess
            MobileApps            = $MobileApps
            CISBaselines          = $CISBaselines
            All                   = $All
            ReportOutputPath      = $ReportOutputPath
            ReportFormats         = $ReportFormats
            WhatIfEnabled         = [bool]$WhatIfPreference
            CommandRuntime        = $PSCmdlet
        }
        $settings = Resolve-HydrationExecutionSettings @resolveSettingsParams

        Write-HydrationExecutionSettingsSummary -Settings $settings
        $platformFilters = Get-HydrationPlatformFilters -Platforms $settings.platforms
        $effectiveWhatIfEnabled = [bool]$WhatIfPreference -or ($settings.options.dryRun -eq $true)
        $effectiveVerboseEnabled = ($VerbosePreference -eq 'Continue') -or ($settings.options.verbose -eq $true)
        if ($settings.options.verbose -eq $true -and $VerbosePreference -ne 'Continue') {
            $VerbosePreference = 'Continue'
            Write-Verbose 'Verbose output enabled for this hydration run'
        }

        # Apply options from settings
        $createEnabled = $settings.options.create -eq $true
        $deleteEnabled = $settings.options.delete -eq $true
        $forceDelete = $settings.options.force -eq $true
        $RemoveExisting = $deleteEnabled

        $testOperationSettingsParams = @{
            CreateEnabled = $createEnabled
            DeleteEnabled = $deleteEnabled
            ForceDelete   = $forceDelete
            WhatIfEnabled = $effectiveWhatIfEnabled
            PSCmdlet      = $PSCmdlet
        }
        if (-not (Test-HydrationOperationSettings @testOperationSettingsParams)) {
            return
        }

        $isConditionalAccessOnly =
        $settings.imports.conditionalAccess -and
        -not $settings.imports.openIntuneBaseline -and
        -not $settings.imports.complianceTemplates -and
        -not $settings.imports.appProtection -and
        -not $settings.imports.notificationTemplates -and
        -not $settings.imports.enrollmentProfiles -and
        -not $settings.imports.dynamicGroups -and
        -not $settings.imports.staticGroups -and
        -not $settings.imports.deviceFilters -and
        -not $settings.imports.mobileApps -and
        -not $settings.imports.cisBaselines

        $scopeProfile = if ($isConditionalAccessOnly) { 'ConditionalAccess' } else { 'Hydration' }
        $requiredScopes = Get-HydrationGraphScopes -Profile $scopeProfile
        $requiredAccessChecks = @(Get-HydrationGraphAccessCheck -Imports $settings.imports)

        # Reset session state at start of hydration run (logging, generated scripts tracking, connection state)
        $script:GeneratedScriptsPath = $null
        $script:GeneratedScriptsNoticeWritten = $false

        # Initialize logging (after applying verbose setting)
        Initialize-HydrationLogging -EnableVerbose:$effectiveVerboseEnabled

        Write-HydrationLog -Message '=== Intune Hydration Kit Started ===' -Level Info

        Write-HydrationLog -Message "Loaded settings for tenant: $(Get-ObfuscatedTenantId -TenantId $settings.tenant.tenantId)" -Level Info

        if ($effectiveWhatIfEnabled) {
            Write-HydrationLog -Message 'Running in DRY-RUN mode - no changes will be made' -Level Warning
        }

        if ($RemoveExisting) {
            if (-not $createEnabled) {
                Write-HydrationLog -Message 'DELETE-ONLY mode - configurations will be deleted without recreation' -Level Warning
            } else {
                Write-HydrationLog -Message 'Remove existing enabled - matching configurations will be deleted before import' -Level Warning
            }
        }

        # Initialize results tracking
        $allResults = @()

        # Authenticate
        Write-HydrationLog -Message 'Authenticating to Microsoft Graph' -Level Info

        $getAuthParams = @{
            AuthenticationSettings = $settings.authentication
            TenantId               = $settings.tenant.tenantId
        }
        $authParams = Get-HydrationAuthParameters @getAuthParams
        $authParams['Verbose'] = $effectiveVerboseEnabled
        $authParams['ScopeProfile'] = $scopeProfile

        # Always connect to Graph API (needed for dry-run to check existing policies)
        Connect-IntuneHydration @authParams

        # Pre-flight checks
        Write-HydrationLog -Message 'Running pre-flight checks' -Level Info

        # Always run pre-flight checks (read-only operations)
        Test-IntunePrerequisites -RequiredScopes $requiredScopes -RequiredAccessChecks $requiredAccessChecks -Verbose:$effectiveVerboseEnabled | Out-Null

        # Dynamic Groups
        if ($settings.imports.dynamicGroups) {
            $joinPathParams = @{
                Path      = $moduleRoot
                ChildPath = 'Templates/DynamicGroups'
            }
            $dynamicGroupTemplatePath = Join-Path @joinPathParams
            $dynamicGroupStepParams = @{
                StepLabel      = 'Dynamic Groups'
                GroupType      = 'Dynamic'
                TemplatePath   = $dynamicGroupTemplatePath
                Platforms      = $platformFilters.Groups
                RemoveExisting = $RemoveExisting
                WhatIfEnabled  = $effectiveWhatIfEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Invoke-HydrationGroupStep @dynamicGroupStepParams) -StepName 'Dynamic group'
        }

        # Static Groups
        if ($settings.imports.staticGroups) {
            $joinPathParams = @{
                Path      = $moduleRoot
                ChildPath = 'Templates/StaticGroups'
            }
            $staticGroupTemplatePath = Join-Path @joinPathParams
            $staticGroupStepParams = @{
                StepLabel      = 'Static Groups'
                GroupType      = 'Static'
                TemplatePath   = $staticGroupTemplatePath
                Platforms      = $platformFilters.Groups
                RemoveExisting = $RemoveExisting
                WhatIfEnabled  = $effectiveWhatIfEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Invoke-HydrationGroupStep @staticGroupStepParams) -StepName 'Static group'
        }

        # Device Filters
        if ($settings.imports.deviceFilters) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Creating' }) Device Filters" -Level Info

            $filterParams = @{
                Platform       = $platformFilters.DeviceFilters
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneDeviceFilter @filterParams) -StepName 'Device filter'
        }

        # OpenIntuneBaseline
        if ($settings.imports.openIntuneBaseline) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) OpenIntuneBaseline policies" -Level Info

            $baselineParams = @{
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Platform       = $platformFilters.Baseline
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneBaseline @baselineParams) -StepName 'Baseline'
        }

        # CIS Baselines
        if ($settings.imports.cisBaselines) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) CIS Baseline policies" -Level Info

            $cisParams = @{
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Platform       = $platformFilters.CISBaseline
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-CISBaseline @cisParams) -StepName 'CIS baseline'
        }

        # Compliance Templates
        if ($settings.imports.complianceTemplates) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) Compliance templates" -Level Info

            $complianceParams = @{
                Platform       = $platformFilters.Compliance
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneCompliancePolicy @complianceParams) -StepName 'Compliance policy'
        }

        # Notification Templates
        if ($settings.imports.notificationTemplates) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) Notification Templates" -Level Info

            $notificationParams = @{
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneNotificationTemplate @notificationParams) -StepName 'Notification template'
        }

        # App Protection Policies (MAM)
        if ($settings.imports.appProtection) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) App Protection policies" -Level Info

            $mamParams = @{
                Platform       = $platformFilters.AppProtection
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneAppProtectionPolicy @mamParams) -StepName 'App protection policy'
        }

        # Enrollment Profiles
        if ($settings.imports.enrollmentProfiles) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) Enrollment Profiles" -Level Info

            $enrollmentParams = @{
                Platform       = $platformFilters.EnrollmentProfiles
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneEnrollmentProfile @enrollmentParams) -StepName 'Enrollment profile'
        }

        # Conditional Access Starter Pack
        if ($settings.imports.conditionalAccess) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) Conditional Access Starter Pack" -Level Info

            $caParams = @{
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneConditionalAccessPolicy @caParams) -StepName 'Conditional access'
        }

        # Mobile Apps
        if ($settings.imports.mobileApps) {
            Write-HydrationLog -Message "$(if ($RemoveExisting) { 'Deleting' } else { 'Importing' }) Mobile Apps" -Level Info

            $selectedPlatforms = @($settings.platforms)
            $windowsSelected = Test-PlatformSelected -SelectedPlatforms $selectedPlatforms -PlatformName 'Windows'
            $macOSSelected = Test-PlatformSelected -SelectedPlatforms $selectedPlatforms -PlatformName 'macOS'
            $mobileAppConfiguration = Get-MobileAppImportConfiguration -Settings $settings

            if ($macOSSelected) {
                Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneMobileApp -Platform @('macOS') -RemoveExisting:$RemoveExisting -WhatIf:$effectiveWhatIfEnabled -Verbose:$effectiveVerboseEnabled) -StepName 'Mobile app (macOS)'
            }

            if ($windowsSelected) {
                Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneMobileApp -Platform @('Windows') -TemplateId @('AdobeAcrobatReaderDC', 'CompanyPortal', 'PowerShell', 'SpotifyMusicAndPodcasts', 'WhatsApp', 'M365Apps') -RemoveExisting:$RemoveExisting -WhatIf:$effectiveWhatIfEnabled -Verbose:$effectiveVerboseEnabled) -StepName 'Mobile app (Windows)'

                $winGetAppParams = @{
                    RemoveExisting     = $RemoveExisting
                    WhatIf             = $effectiveWhatIfEnabled
                    Verbose            = $effectiveVerboseEnabled
                    RemediationEnabled = $mobileAppConfiguration.remediationEnabled
                }

                if (-not [string]::IsNullOrWhiteSpace($mobileAppConfiguration.presetId)) {
                    $winGetAppParams['PresetId'] = $mobileAppConfiguration.presetId
                }

                if ($mobileAppConfiguration.templateIds.Count -gt 0) {
                    $winGetAppParams['TemplateId'] = $mobileAppConfiguration.templateIds
                }

                Add-HydrationStepResults -Results ([ref]$allResults) -StepResults @(Import-IntuneWinGetApp @winGetAppParams) -StepName 'WinGet app'
            }
        }

        $summaryParams = @{
            Settings      = $settings
            Results       = $allResults
            StartTime     = $executionStartTime
            WhatIfEnabled = $effectiveWhatIfEnabled
            Verbose       = $effectiveVerboseEnabled
        }
        $summaryOutput = Write-HydrationExecutionSummary @summaryParams
        $summary = $summaryOutput.Summary
        $reportPath = $summaryOutput.ReportPath
        $jsonReportPath = $summaryOutput.JsonReportPath
        $elapsedTime = $summaryOutput.ElapsedTime
        $elapsedTimeDisplay = $summaryOutput.ElapsedTimeDisplay

        # Return summary object (functions shouldn't call exit)
        return @{
            Success            = $summary.Failed -eq 0
            Summary            = $summary
            Results            = $allResults
            ReportPath         = $reportPath
            JsonReportPath     = $jsonReportPath
            ElapsedTime        = $elapsedTime
            ElapsedTimeDisplay = $elapsedTimeDisplay
        }
    } catch {
        if ($_.FullyQualifiedErrorId -notlike '*PrerequisiteCheckFailed*') {
            Write-HydrationLog -Message "Fatal error: $_" -Level Error
        }
        throw
    }

    #endregion
}
