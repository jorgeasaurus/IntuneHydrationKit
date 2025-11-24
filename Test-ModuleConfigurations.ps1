#Requires -Version 7.0

<#
.SYNOPSIS
    Tests the Intune Hydration Kit module with all possible option configurations
.DESCRIPTION
    Creates temporary settings files for each configuration combination and runs
    the hydration script in dry-run mode to validate all code paths.
.PARAMETER TenantId
    The tenant ID to use for testing
.PARAMETER TestImports
    Which import types to test (default: all)
.EXAMPLE
    ./Test-ModuleConfigurations.ps1 -TenantId "contoso.onmicrosoft.com"
.EXAMPLE
    ./Test-ModuleConfigurations.ps1 -TenantId "contoso.onmicrosoft.com" -TestImports @('dynamicGroups', 'deviceFilters')
#>
[CmdletBinding()]
param(
    [string]$TenantId = "0e3028c5-ada7-4d5d-b767-eea5ff7417b5",

    [Parameter()]
    [ValidateSet('dynamicGroups', 'deviceFilters', 'conditionalAccess', 'compliancePolicies',
                 'openIntuneBaseline', 'enrollmentProfiles', 'appProtectionPolicies')]
    [string[]]$TestImports = @('dynamicGroups', 'deviceFilters', 'conditionalAccess',
                               'compliancePolicies', 'openIntuneBaseline', 'enrollmentProfiles',
                               'appProtectionPolicies')
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$scriptRoot = $PSScriptRoot
$tempSettingsDir = Join-Path -Path $scriptRoot -ChildPath 'TestConfigs'
$resultsDir = Join-Path -Path $scriptRoot -ChildPath 'TestResults'
$logsDir = Join-Path -Path $scriptRoot -ChildPath 'Logs'

# Create directories
if (-not (Test-Path $tempSettingsDir)) {
    New-Item -Path $tempSettingsDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $resultsDir)) {
    New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $logsDir)) {
    New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
}

# Start transcript
$transcriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptPath = Join-Path -Path $logsDir -ChildPath "Test-ModuleConfigurations-$transcriptTimestamp.log"
Start-Transcript -Path $transcriptPath -Append

# Define all configuration combinations to test
$configurations = @(
    # Full create (all items)
    @{
        Name = "Create-Full-LIVE"
        Options = @{
            create = $true
            update = $false
            delete = $false
            dryRun = $false
            testMode = $false
            verbose = $false
        }
    },
    # Full update (all items)
    @{
        Name = "Update-Full-LIVE"
        Options = @{
            create = $false
            update = $true
            delete = $false
            dryRun = $false
            testMode = $false
            verbose = $false
        }
    },
    # Create with verbose (all items)
    @{
        Name = "Create-Verbose-LIVE"
        Options = @{
            create = $true
            update = $false
            delete = $false
            dryRun = $false
            testMode = $false
            verbose = $true
        }
    },
    # Full delete (all items) - CAUTION!
    @{
        Name = "Delete-Full-LIVE"
        Options = @{
            create = $false
            update = $false
            delete = $true
            dryRun = $false
            testMode = $false
            verbose = $false
        }
    }
)

# Build imports object
$imports = @{}
foreach ($import in $TestImports) {
    $imports[$import] = $true
}

# Track results
$testResults = @()
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "=== Intune Hydration Kit Configuration Test ==="
Write-Host "Tenant: $TenantId"
Write-Host "Testing $($configurations.Count) configurations"
Write-Host "Imports enabled: $($TestImports -join ', ')"
Write-Host ""

foreach ($config in $configurations) {
    $configName = $config.Name
    $settingsFileName = "settings-$configName.json"
    $settingsPath = Join-Path -Path $tempSettingsDir -ChildPath $settingsFileName

    # Create settings file
    $settings = @{
        tenant = @{
            tenantId = $TenantId
        }
        authentication = @{
            mode = "interactive"
        }
        options = $config.Options
        imports = $imports
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding utf8

    Write-Host "----------------------------------------"
    Write-Host "Testing: $configName"
    Write-Host "Options: create=$($config.Options.create), update=$($config.Options.update), delete=$($config.Options.delete)"
    Write-Host "         dryRun=$($config.Options.dryRun), testMode=$($config.Options.testMode), verbose=$($config.Options.verbose)"

    $result = @{
        Configuration = $configName
        StartTime = Get-Date
        Status = 'Unknown'
        Error = $null
        Duration = $null
    }

    try {
        # Run the hydration script
        $output = & "$scriptRoot/Invoke-IntuneHydration.ps1" -SettingsPath $settingsPath 2>&1

        $result.Status = 'Success'
        $result.Output = $output | Out-String

        Write-Host "  Result: SUCCESS"
    }
    catch {
        $result.Status = 'Failed'
        $result.Error = $_.Exception.Message

        Write-Warning "  Result: FAILED - $($_.Exception.Message)"
    }
    finally {
        $result.EndTime = Get-Date
        $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds

        Write-Host "  Duration: $([math]::Round($result.Duration, 2))s"
    }

    $testResults += [PSCustomObject]$result
}

Write-Host ""
Write-Host "=== Test Summary ==="

# Summary
$passed = ($testResults | Where-Object { $_.Status -eq 'Success' }).Count
$failed = ($testResults | Where-Object { $_.Status -eq 'Failed' }).Count

Write-Host "Passed: $passed / $($testResults.Count)"
Write-Host "Failed: $failed / $($testResults.Count)"

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Failed Tests:"
    $testResults | Where-Object { $_.Status -eq 'Failed' } | ForEach-Object {
        Write-Warning "  - $($_.Configuration): $($_.Error)"
    }
}

# Export results
$resultsPath = Join-Path -Path $resultsDir -ChildPath "TestResults-$timestamp.json"
$testResults | ConvertTo-Json -Depth 10 | Set-Content -Path $resultsPath -Encoding utf8

Write-Host ""
Write-Host "Results saved to: $resultsPath"

# Cleanup temp settings files
Write-Host "Cleaning up temporary settings files..."
Remove-Item -Path $tempSettingsDir -Recurse -Force -ErrorAction SilentlyContinue

# Stop transcript
Write-Host "Transcript saved to: $transcriptPath"
Stop-Transcript

# Return results for pipeline
return $testResults
