#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Wrapper script for Intune tenant hydration (backward compatibility)
.DESCRIPTION
    This script provides backward compatibility for users who clone the repository
    and run the script directly. It imports the IntuneHydrationKit module and calls
    the Invoke-IntuneHydration function with all provided parameters.

    For new users, consider installing from PSGallery:
        Install-Module IntuneHydrationKit
        Invoke-IntuneHydration
.PARAMETER SettingsPath
    Path to the settings JSON file. Use this for settings file-based invocation.
.PARAMETER TenantId
    Azure AD tenant ID (GUID). Required for parameter-based invocation.
.PARAMETER TenantName
    Tenant name for display purposes (e.g., contoso.onmicrosoft.com)
.PARAMETER Interactive
    Use interactive authentication (browser-based login).
.PARAMETER ClientId
    Application (client) ID for service principal authentication.
.PARAMETER ClientSecret
    Client secret for service principal authentication (SecureString).
.PARAMETER Environment
    Azure cloud environment. Valid values: Global, USGov, USGovDoD, Germany, China
.PARAMETER Create
    Enable creation of configurations
.PARAMETER Delete
    Enable deletion of kit-created configurations
.PARAMETER Force
    Skip confirmation prompt when running in delete mode
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
    Process static groups
.PARAMETER DeviceFilters
    Process device filters
.PARAMETER ConditionalAccess
    Process Conditional Access starter pack policies
.PARAMETER MobileApps
    Process mobile app templates
.PARAMETER Remediations
    Process bundled, unassigned Proactive Windows Remediations.
.PARAMETER CISBaselines
    Process bundled CIS baseline policies
.PARAMETER All
    Enable all targets
.PARAMETER Platform
    Filter imports by platform. Valid values: Windows, macOS, iOS, Android, Linux, All.
.PARAMETER ReportOutputPath
    Output directory for reports
.PARAMETER ReportFormats
    Report formats to generate (markdown, json)
.PARAMETER WhatIf
    Run in dry-run mode without making changes to Intune
.EXAMPLE
    ./Invoke-IntuneHydration.ps1

    Launch the interactive console wizard.
.EXAMPLE
    ./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json

    Run using settings from a JSON file.
.EXAMPLE
    ./Invoke-IntuneHydration.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -Interactive -Create -All

    Run with all imports enabled using interactive authentication.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'InteractiveTui')]
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
    [switch]$VerboseOutput,

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
    [switch]$Remediations,

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

# Import the module from the same directory as this script
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'IntuneHydrationKit.psd1'
if (Test-Path -Path $modulePath) {
    Import-Module -Name $modulePath -Force
} else {
    throw "Module not found at: $modulePath. Ensure IntuneHydrationKit.psd1 is in the same directory as this script."
}

# Build parameters to pass to the function
$invokeParams = @{}

# Add all bound parameters except common parameters
$PSBoundParameters.GetEnumerator() | ForEach-Object {
    if ($_.Key -notin @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm')) {
        $invokeParams[$_.Key] = $_.Value
    }
}

# Handle WhatIf separately to ensure it's passed correctly
if ($WhatIfPreference) {
    $invokeParams['WhatIf'] = $true
}

# Call the module function
$result = Invoke-IntuneHydration @invokeParams

# Exit with appropriate code based on result
if ($result.Success) {
    exit 0
} else {
    exit 1
}
