#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Wrapper script for Intune tenant hydration.
.DESCRIPTION
    Provides backward compatibility for users who clone the repository and run the
    script directly. The script imports the local IntuneHydrationKit module and
    forwards parameters to the module's Invoke-IntuneHydration function.
.PARAMETER SettingsPath
    Path to the settings JSON file. Use this for settings file-based invocation.
.PARAMETER TenantId
    Azure AD tenant ID (GUID). Required for parameter-based invocation.
.PARAMETER TenantName
    Tenant name for display purposes.
.PARAMETER Interactive
    Use interactive authentication.
.PARAMETER ClientId
    Application client ID for service principal authentication.
.PARAMETER ClientSecret
    Client secret for service principal authentication.
.PARAMETER Environment
    Azure cloud environment.
.PARAMETER Create
    Enable creation of configurations.
.PARAMETER Delete
    Enable deletion of kit-created configurations.
.PARAMETER Force
    Skip confirmation prompt when running in delete mode.
.PARAMETER OpenIntuneBaseline
    Process OpenIntuneBaseline policies.
.PARAMETER ComplianceTemplates
    Process compliance policy templates.
.PARAMETER AppProtection
    Process app protection policies.
.PARAMETER NotificationTemplates
    Process notification templates.
.PARAMETER EnrollmentProfiles
    Process enrollment profiles.
.PARAMETER DynamicGroups
    Process dynamic groups.
.PARAMETER StaticGroups
    Process static groups.
.PARAMETER DeviceFilters
    Process device filters.
.PARAMETER ConditionalAccess
    Process Conditional Access starter pack policies.
.PARAMETER MobileApps
    Process mobile app templates.
.PARAMETER CISBaselines
    Process CIS baseline policies.
.PARAMETER All
    Enable all targets.
.PARAMETER Platform
    Filter imports by platform.
.PARAMETER ReportOutputPath
    Output directory for reports.
.PARAMETER ReportFormats
    Report formats to generate.
.EXAMPLE
    ./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -WhatIf
.EXAMPLE
    ./Invoke-IntuneHydration.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -Interactive -Create -All
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'SettingsFile')]
param(
    [Parameter(ParameterSetName = 'SettingsFile', Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path $_ })]
    [string]$SettingsPath,

    [Parameter(ParameterSetName = 'Interactive', Mandatory = $true)]
    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'ServicePrincipal')]
    [string]$TenantName,

    [Parameter(ParameterSetName = 'Interactive', Mandatory = $true)]
    [switch]$Interactive,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $true)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $true)]
    [SecureString]$ClientSecret,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'ServicePrincipal')]
    [ValidateSet('Global', 'USGov', 'USGovDoD', 'Germany', 'China')]
    [string]$Environment = 'Global',

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

    [Parameter(ParameterSetName = 'SettingsFile')]
    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'ServicePrincipal')]
    [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')]
    [string[]]$Platform = @('All'),

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'ServicePrincipal')]
    [string]$ReportOutputPath,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'ServicePrincipal')]
    [ValidateSet('markdown', 'json')]
    [string[]]$ReportFormats
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'IntuneHydrationKit.psd1'
if (-not (Test-Path -Path $modulePath -PathType Leaf)) {
    throw "Module not found at: $modulePath. Ensure IntuneHydrationKit.psd1 is in the same directory as this script."
}

Import-Module -Name $modulePath -Force

$commonParameters = @(
    'Verbose'
    'Debug'
    'ErrorAction'
    'WarningAction'
    'InformationAction'
    'ErrorVariable'
    'WarningVariable'
    'InformationVariable'
    'OutVariable'
    'OutBuffer'
    'PipelineVariable'
    'ProgressAction'
    'WhatIf'
    'Confirm'
)

$invokeParams = @{}
foreach ($parameter in $PSBoundParameters.GetEnumerator()) {
    if ($parameter.Key -notin $commonParameters) {
        $invokeParams[$parameter.Key] = $parameter.Value
    }
}

if ($PSBoundParameters.ContainsKey('WhatIf')) {
    $invokeParams['WhatIf'] = [bool]$PSBoundParameters['WhatIf']
}

if ($PSBoundParameters.ContainsKey('Confirm')) {
    $invokeParams['Confirm'] = [bool]$PSBoundParameters['Confirm']
}

$result = Invoke-IntuneHydration @invokeParams

if ($result.Success) {
    exit 0
}

exit 1
