function Resolve-HydrationExecutionSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParameterSetName,

        [Parameter()]
        [string]$SettingsPath,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [string[]]$Platform,

        [Parameter()]
        [bool]$PlatformSpecified,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$TenantName,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [SecureString]$ClientSecret,

        [Parameter()]
        [string]$Environment,

        [Parameter()]
        [switch]$Create,

        [Parameter()]
        [switch]$Delete,

        [Parameter()]
        [switch]$VerboseOutput,

        [Parameter()]
        [switch]$OpenIntuneBaseline,

        [Parameter()]
        [switch]$ComplianceTemplates,

        [Parameter()]
        [switch]$AppProtection,

        [Parameter()]
        [switch]$NotificationTemplates,

        [Parameter()]
        [switch]$EnrollmentProfiles,

        [Parameter()]
        [switch]$DynamicGroups,

        [Parameter()]
        [switch]$StaticGroups,

        [Parameter()]
        [switch]$DeviceFilters,

        [Parameter()]
        [switch]$ConditionalAccess,

        [Parameter()]
        [switch]$MobileApps,

        [Parameter()]
        [switch]$Remediations,

        [Parameter()]
        [switch]$CISBaselines,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [string]$ReportOutputPath,

        [Parameter()]
        [string[]]$ReportFormats,

        [Parameter()]
        [bool]$WhatIfEnabled,

        [Parameter()]
        [bool]$CommonVerboseEnabled,

        [Parameter()]
        [hashtable]$TuiSelection,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$CommandRuntime
    )

    if ($ParameterSetName -eq 'InteractiveTui') {
        if (-not $TuiSelection) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TUI selection data is required for interactive TUI invocation.'),
                'TuiSelectionRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $null
            )
            $CommandRuntime.ThrowTerminatingError($errorRecord)
        }

        $operation = $TuiSelection.Operation
        $options = @{
            create       = [bool]$operation.create
            delete       = [bool]$operation.delete
            force        = $false
            dryRun       = [bool]$operation.dryRun -or $WhatIfEnabled
            verbose      = [bool]$TuiSelection.VerboseEnabled -or $CommonVerboseEnabled
            forceConsent = [bool]$TuiSelection.ConsentPromptEnabled
        }
        $resolvedPlatforms = if ($TuiSelection.Platforms) { $TuiSelection.Platforms } else { @('All') }
        $resolvedEnvironment = if ($TuiSelection.Environment) { $TuiSelection.Environment } else { 'Global' }

        return New-HydrationExecutionSetting `
            -TenantId $TuiSelection.TenantId `
            -AuthenticationMode 'interactive' `
            -Environment $resolvedEnvironment `
            -Options $options `
            -Imports $TuiSelection.Imports `
            -Platforms $resolvedPlatforms `
            -ReportFormats @('markdown')
    }

    if ($ParameterSetName -eq 'SettingsFile') {
        $settings = Import-HydrationSettings -Path $SettingsPath
        Write-Information (Format-HydrationDisplayMessage -Message "Loaded settings from: $SettingsPath" -Style 'Info' -Emoji '📄') -InformationAction Continue

        if (-not $settings.options) {
            $settings['options'] = @{}
        }

        $settings.options.force = $Force.IsPresent -or ($settings.options.Contains('force') -and $settings.options.force)
        if ($Delete.IsPresent) {
            $settings.options.create = $false
            $settings.options.delete = $true
        }

        if ($PlatformSpecified) {
            $settings['platforms'] = $Platform
        } elseif (-not $settings.platforms) {
            $settings['platforms'] = @('All')
        }

        return New-HydrationExecutionSetting `
            -TenantId $settings.tenant.tenantId `
            -TenantName $settings.tenant.tenantName `
            -AuthenticationMode $settings.authentication.mode `
            -ClientId $settings.authentication.clientId `
            -ClientSecret $settings.authentication.clientSecret `
            -Environment $settings.authentication.environment `
            -Options $settings.options `
            -Imports $settings.imports `
            -Platforms $settings.platforms `
            -ReportOutputPath $settings.reporting.outputPath `
            -ReportFormats $settings.reporting.formats `
            -MobileApps $settings.mobileApps
    }

    Write-Information (Format-HydrationDisplayMessage -Message 'Using parameter-based configuration' -Style 'Info' -Emoji '🧩') -InformationAction Continue

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
        remediations          = $All.IsPresent -or $Remediations.IsPresent
        cisBaselines          = $All.IsPresent -or $CISBaselines.IsPresent
    }

    if ($All.IsPresent) {
        Write-Warning 'The -All parameter includes CIS Baselines. This will significantly increase the number of imported items and import time.'
    }

    if (-not ($importsEnabled.Values -contains $true)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("At least one target must be enabled. Use -All or specify a target switch (e.g., -DynamicGroups, -DeviceFilters, etc.)."),
            'NoTargetsEnabled',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null
        )
        $CommandRuntime.ThrowTerminatingError($errorRecord)
    }

    $options = @{
        create       = $Create.IsPresent
        delete       = $Delete.IsPresent
        force        = $Force.IsPresent
        dryRun       = $WhatIfEnabled
        verbose      = $VerboseOutput.IsPresent -or $CommonVerboseEnabled
        forceConsent = $false
    }
    $authenticationMode = if ($Interactive) { 'interactive' } else { 'clientSecret' }
    $resolvedPlatforms = if ($Platform) { $Platform } else { @('All') }
    $resolvedReportFormats = if ($ReportFormats) { $ReportFormats } else { @('markdown') }

    New-HydrationExecutionSetting `
        -TenantId $TenantId `
        -TenantName $TenantName `
        -AuthenticationMode $authenticationMode `
        -ClientId $ClientId `
        -ClientSecret $ClientSecret `
        -Environment $Environment `
        -Options $options `
        -Imports $importsEnabled `
        -Platforms $resolvedPlatforms `
        -ReportOutputPath $ReportOutputPath `
        -ReportFormats $resolvedReportFormats
}
