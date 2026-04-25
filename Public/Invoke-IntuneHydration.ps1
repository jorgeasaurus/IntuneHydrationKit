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

    # Resolve module root - use $script:ModuleRoot if set by psm1, otherwise use PSScriptRoot parent
    $moduleRoot = if ($script:ModuleRoot) {
        $script:ModuleRoot
    } else {
        $splitPathParams = @{
            Path   = $PSScriptRoot
            Parent = $true
        }
        Split-Path @splitPathParams
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
            VerboseOutput         = $VerboseOutput
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

        # Initialize logging (after applying verbose setting)
        # Uses OS temp directory by default (e.g., $env:TEMP/IntuneHydrationKit/Logs on Windows, /tmp/IntuneHydrationKit/Logs on macOS/Linux)
        Initialize-HydrationLogging -EnableVerbose:$effectiveVerboseEnabled

        $logParams = @{
            Message = '=== Intune Hydration Kit Started ==='
            Level   = 'Info'
        }
        Write-HydrationLog @logParams

        $logParams = @{
            Message = "Loaded settings for tenant: $(Get-ObfuscatedTenantId -TenantId $settings.tenant.tenantId)"
            Level   = 'Info'
        }
        Write-HydrationLog @logParams

        if ($effectiveWhatIfEnabled) {
            $logParams = @{
                Message = 'Running in DRY-RUN mode - no changes will be made'
                Level   = 'Warning'
            }
            Write-HydrationLog @logParams
        }

        if ($RemoveExisting) {
            if (-not $createEnabled) {
                $logParams = @{
                    Message = 'DELETE-ONLY mode - configurations will be deleted without recreation'
                    Level   = 'Warning'
                }
                Write-HydrationLog @logParams
            } else {
                $logParams = @{
                    Message = 'Remove existing enabled - matching configurations will be deleted before import'
                    Level   = 'Warning'
                }
                Write-HydrationLog @logParams
            }
        }

        # Initialize results tracking
        $allResults = @()

        # Step 1: Authenticate
        $logParams = @{
            Message = 'Step 1: Authenticating to Microsoft Graph'
            Level   = 'Info'
        }
        Write-HydrationLog @logParams

        $getAuthParams = @{
            AuthenticationSettings = $settings.authentication
            TenantId               = $settings.tenant.tenantId
        }
        $authParams = Get-HydrationAuthParameters @getAuthParams
        $authParams['Verbose'] = $effectiveVerboseEnabled

        # Always connect to Graph API (needed for dry-run to check existing policies)
        Connect-IntuneHydration @authParams

        # Step 2: Pre-flight checks
        $logParams = @{
            Message = 'Step 2: Running pre-flight checks'
            Level   = 'Info'
        }
        Write-HydrationLog @logParams

        # Always run pre-flight checks (read-only operations)
        Test-IntunePrerequisites -Verbose:$effectiveVerboseEnabled | Out-Null

        # Step 3: Dynamic Groups
        if ($settings.imports.dynamicGroups) {
            $joinPathParams = @{
                Path      = $moduleRoot
                ChildPath = 'Templates/DynamicGroups'
            }
            $dynamicGroupTemplatePath = Join-Path @joinPathParams
            $dynamicGroupStepParams = @{
                StepLabel      = 'Step 3'
                GroupType      = 'Dynamic'
                TemplatePath   = $dynamicGroupTemplatePath
                Platforms      = $platformFilters.Groups
                RemoveExisting = $RemoveExisting
                WhatIfEnabled  = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $dynamicGroupResults = @((Invoke-HydrationGroupStep @dynamicGroupStepParams) | Where-Object { $null -ne $_ })
            $allResults += $dynamicGroupResults
        }

        # Step 3b: Static Groups
        if ($settings.imports.staticGroups) {
            $joinPathParams = @{
                Path      = $moduleRoot
                ChildPath = 'Templates/StaticGroups'
            }
            $staticGroupTemplatePath = Join-Path @joinPathParams
            $staticGroupStepParams = @{
                StepLabel      = 'Step 3b'
                GroupType      = 'Static'
                TemplatePath   = $staticGroupTemplatePath
                Platforms      = $platformFilters.Groups
                RemoveExisting = $RemoveExisting
                WhatIfEnabled  = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $staticGroupResults = @((Invoke-HydrationGroupStep @staticGroupStepParams) | Where-Object { $null -ne $_ })
            $allResults += $staticGroupResults
        }

        # Step 4: Device Filters
        if ($settings.imports.deviceFilters) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Creating" }
            $logParams = @{
                Message = "Step 4: $stepAction Device Filters"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $filterParams = @{
                Platform       = $platformFilters.DeviceFilters
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $filterResults = @((Import-IntuneDeviceFilter @filterParams) | Where-Object { $null -ne $_ })
            $allResults += $filterResults
        }

        # Step 5: OpenIntuneBaseline
        if ($settings.imports.openIntuneBaseline) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 5: $stepAction OpenIntuneBaseline policies"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $baselineParams = @{}

            # Import function handles ShouldProcess internally for each policy
            $baselineParams['RemoveExisting'] = $RemoveExisting
            $baselineParams['WhatIf'] = $effectiveWhatIfEnabled
            $baselineParams['Platform'] = $platformFilters.Baseline
            $baselineParams['Verbose'] = $effectiveVerboseEnabled
            $baselineResults = @((Import-IntuneBaseline @baselineParams) | Where-Object { $null -ne $_ })
            $allResults += $baselineResults
        }

        # Step 5b: CIS Baselines
        if ($settings.imports.cisBaselines) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 5b: $stepAction CIS Baseline policies"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $cisParams = @{
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Platform       = $platformFilters.CISBaseline
                Verbose        = $effectiveVerboseEnabled
            }
            $cisResults = @((Import-CISBaseline @cisParams) | Where-Object { $null -ne $_ })
            $allResults += $cisResults
        }

        # Step 6: Compliance Templates
        if ($settings.imports.complianceTemplates) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 6: $stepAction Compliance templates"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $complianceParams = @{
                Platform       = $platformFilters.Compliance
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $complianceResults = @((Import-IntuneCompliancePolicy @complianceParams) | Where-Object { $null -ne $_ })
            $allResults += $complianceResults
        }

        # Step 7: Notification Templates
        if ($settings.imports.notificationTemplates) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 7: $stepAction Notification Templates"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $notificationParams = @{
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $notificationResults = @((Import-IntuneNotificationTemplate @notificationParams) | Where-Object { $null -ne $_ })
            $allResults += $notificationResults
        }

        # Step 8: App Protection Policies (MAM)
        if ($settings.imports.appProtection) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 8: $stepAction App Protection policies"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $mamParams = @{
                Platform       = $platformFilters.AppProtection
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $mamResults = @((Import-IntuneAppProtectionPolicy @mamParams) | Where-Object { $null -ne $_ })
            $allResults += $mamResults
        }

        # Step 9: Enrollment Profiles
        if ($settings.imports.enrollmentProfiles) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 9: $stepAction Enrollment Profiles"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $enrollmentParams = @{
                Platform       = $platformFilters.EnrollmentProfiles
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $enrollmentResults = @((Import-IntuneEnrollmentProfile @enrollmentParams) | Where-Object { $null -ne $_ })
            $allResults += $enrollmentResults
        }

        # Step 10: Conditional Access Starter Pack
        if ($settings.imports.conditionalAccess) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 10: $stepAction Conditional Access Starter Pack"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $caParams = @{
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $caResults = @((Import-IntuneConditionalAccessPolicy @caParams) | Where-Object { $null -ne $_ })
            $allResults += $caResults
        }

        # Step 11: Mobile Apps
        if ($settings.imports.mobileApps) {
            $stepAction = if ($RemoveExisting) { "Deleting" } else { "Importing" }
            $logParams = @{
                Message = "Step 11: $stepAction Mobile Apps"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            $mobileAppParams = @{
                Platform       = $platformFilters.MobileApps
                RemoveExisting = $RemoveExisting
                WhatIf         = $effectiveWhatIfEnabled
                Verbose        = $effectiveVerboseEnabled
            }
            $mobileAppResults = @((Import-IntuneMobileApp @mobileAppParams) | Where-Object { $null -ne $_ })
            $allResults += $mobileAppResults
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
        $logParams = @{
            Message = "Fatal error: $_"
            Level   = 'Error'
        }
        Write-HydrationLog @logParams
        throw
    }

    #endregion
}
