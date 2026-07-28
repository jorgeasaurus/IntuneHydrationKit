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
    TenantId  = $null
}

# Module-level state for logging
$script:LogPath = $null
$script:VerboseLogging = $false
$script:CurrentLogFile = $null
$script:HydrationSessionId = $null
$script:GeneratedScriptsPath = $null
$script:GeneratedScriptsNoticeWritten = $false

# Module-level state for Graph environment
$script:GraphEnvironment = $null
$script:GraphEndpoint = $null

# Graph API batch operation settings
$script:MaxBatchSize = 10  # Graph API batch limit (max 20, using 10 for safety)

# Prefix prepended to every imported resource's displayName/name for easy identification
$script:ImportPrefix = '[IHD] '

# Hydration kit marker embedded in descriptions/notes to identify objects created by this kit
$script:HydrationMarker = 'Imported by Intune Hydration Kit'
$script:HydrationMarkerAlt = 'Imported by Intune-Hydration-Kit'

# Import private functions
$privatePath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private'
if (Test-Path -Path $privatePath) {
    $privateFiles = Get-ChildItem -Path $privatePath -Filter '*.ps1' -File -Recurse
    foreach ($file in $privateFiles) {
        try {
            . $file.FullName
            Write-Verbose "Imported private function: $($file.BaseName)"
        } catch {
            throw [System.Exception]::new(
                "Failed to import private function '$($file.FullName)': $($_.Exception.Message)",
                $_.Exception
            )
        }
    }
}

# Import public functions
$publicPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public'
if (Test-Path -Path $publicPath) {
    $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -File -Recurse
    foreach ($file in $publicFiles) {
        try {
            . $file.FullName
            Write-Verbose "Imported public function: $($file.BaseName)"
        } catch {
            throw [System.Exception]::new(
                "Failed to import public function '$($file.FullName)': $($_.Exception.Message)",
                $_.Exception
            )
        }
    }
}

# Define public functions to export (must match FunctionsToExport in .psd1)
$publicFunctions = @(
        'Connect-IntuneHydration',
        'Get-GraphErrorMessage',
        'Get-ObfuscatedTenantId',
        'Get-OpenIntuneBaseline',
        'Get-ResultSummary',
        'Import-CISBaseline',
        'Import-HydrationSettings',
        'Import-IntuneAppProtectionPolicy',
        'Import-IntuneBaseline',
        'Import-IntuneCompliancePolicy',
        'Import-IntuneConditionalAccessPolicy',
        'Import-IntuneDeviceFilter',
        'Import-IntuneEnrollmentProfile',
        'Import-IntuneMobileApp',
        'Import-IntuneNotificationTemplate',
        'Import-IntuneRemediation',
        'Import-IntuneWinGetApp',
        'Initialize-HydrationLogging',
        'Invoke-IntuneHydration',
        'New-HydrationResult',
        'New-IntuneDynamicGroup',
        'New-IntuneStaticGroup',
        'Test-HydrationKitObject',
        'Test-IntunePrerequisites',
        'Write-HydrationLog'
)

# Export functions
Export-ModuleMember -Function $publicFunctions
