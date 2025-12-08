#Requires -Version 7.0

<#
.SYNOPSIS
    Root module for IntuneHydrationKit
.DESCRIPTION
    Hydrates Microsoft Intune tenants with best-practice baseline configurations.
#>

# Module-level variables
$script:ModuleRoot = $PSScriptRoot
$script:TemplatesPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Templates'
$script:HydrationState = @{
    Connected = $false
    TenantId = $null
    Results = @{
        Groups = @()
        Policies = @()
        Baselines = @()
        Profiles = @()
        ConditionalAccess = @()
        Errors = @()
        Warnings = @()
    }
}

# Module-level state for logging
$script:LogPath = $null
$script:VerboseLogging = $false
$script:CurrentLogFile = $null

# Module-level state for Graph environment
$script:GraphEnvironment = $null
$script:GraphEndpoint = $null

# Import private functions
$privatePath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private'
if (Test-Path -Path $privatePath) {
    $privateFiles = Get-ChildItem -Path $privatePath -Filter '*.ps1' -File
    foreach ($file in $privateFiles) {
        try {
            . $file.FullName
            Write-Verbose "Imported private function: $($file.BaseName)"
        }
        catch {
            Write-Error "Failed to import private function $($file.FullName): $_"
        }
    }
}

# Import public functions
$publicPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public'
if (Test-Path -Path $publicPath) {
    $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -File
    foreach ($file in $publicFiles) {
        try {
            . $file.FullName
            Write-Verbose "Imported public function: $($file.BaseName)"
        }
        catch {
            Write-Error "Failed to import public function $($file.FullName): $_"
        }
    }
}

# Define public functions to export (must match FunctionsToExport in .psd1)
$publicFunctions = @(
    # Main entry point
    'Invoke-IntuneHydration',
    # Core hydration functions
    'Connect-IntuneHydration',
    'Test-IntunePrerequisites',
    # Import functions
    'New-IntuneDynamicGroup',
    'New-IntuneStaticGroup',
    'Get-OpenIntuneBaseline',
    'Import-IntuneBaseline',
    'Import-IntuneCompliancePolicy',
    'Import-IntuneAppProtectionPolicy',
    'Import-IntuneNotificationTemplate',
    'Import-IntuneEnrollmentProfile',
    'Import-IntuneDeviceFilter',
    'Import-IntuneConditionalAccessPolicy',
    'Import-IntuneMobileApp',
    # Helper functions
    'Initialize-HydrationLogging',
    'Write-HydrationLog',
    'Import-HydrationSettings',
    # Result helpers (used by orchestrator)
    'New-HydrationResult',
    'Get-ResultSummary',
    'Get-GraphErrorMessage',
    # Safety helpers (used by orchestrator for deletion safety checks)
    'Test-HydrationKitObject',
    # Utility helpers
    'Get-ObfuscatedTenantId'
)

# Export functions
Export-ModuleMember -Function $publicFunctions
