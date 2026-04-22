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
        [switch]$CISBaselines,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [string]$ReportOutputPath,

        [Parameter()]
        [string[]]$ReportFormats,

        [Parameter()]
        [bool]$WhatIfEnabled,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$PSCmdlet
    )

    if ($ParameterSetName -eq 'SettingsFile') {
        $settings = Import-HydrationSettings -Path $SettingsPath
        Write-Host "Loaded settings from: $SettingsPath" -InformationAction Continue

        if (-not $settings.options) {
            $settings['options'] = @{}
        }

        $settings.options.force = $Force.IsPresent -or ($settings.options.ContainsKey('force') -and $settings.options.force)

        if ($Platform -and $Platform -notcontains 'All') {
            $settings['platforms'] = $Platform
        } elseif (-not $settings.platforms) {
            $settings['platforms'] = @('All')
        }

        return $settings
    }

    Write-Host "Using parameter-based configuration" -InformationAction Continue

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
        cisBaselines          = $All.IsPresent -or $CISBaselines.IsPresent
    }

    if ($All.IsPresent) {
        Write-Warning "The -All parameter includes CIS Baselines (728+ policies). This will significantly increase the number of imported items and import time."
    }

    if (-not ($importsEnabled.Values -contains $true)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("At least one target must be enabled. Use -All or specify a target switch (e.g., -DynamicGroups, -DeviceFilters, etc.)."),
            'NoTargetsEnabled',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return @{
        tenant         = @{
            tenantId   = $TenantId
            tenantName = $TenantName
        }
        authentication = @{
            mode         = if ($Interactive) { 'interactive' } else { 'clientSecret' }
            clientId     = $ClientId
            clientSecret = if ($ClientSecret) { [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)) } else { $null }
            environment  = $Environment
        }
        options        = @{
            create  = $Create.IsPresent
            delete  = $Delete.IsPresent
            force   = $Force.IsPresent
            dryRun  = $WhatIfEnabled
            verbose = $VerboseOutput.IsPresent
        }
        imports        = $importsEnabled
        reporting      = @{
            outputPath = if ($ReportOutputPath) { $ReportOutputPath } else { $null }
            formats    = if ($ReportFormats) { $ReportFormats } else { @('markdown') }
        }
        platforms      = if ($Platform) { $Platform } else { @('All') }
    }
}
