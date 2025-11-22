<#
.SYNOPSIS
    Validation and testing script for Intune Hydration Kit.

.DESCRIPTION
    Validates PowerShell scripts, modules, and configuration files
    without making actual changes to any Intune tenant.
#>

[CmdletBinding()]
param()

Write-Host "=== Intune Hydration Kit Validation ===" -ForegroundColor Cyan
Write-Host ""

$ErrorCount = 0
$WarningCount = 0
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Test 1: Validate PowerShell syntax
Write-Host "[TEST 1] Validating PowerShell syntax..." -ForegroundColor Yellow

$PSFiles = Get-ChildItem -Path $ScriptRoot -Recurse -Filter "*.ps*1" -File
foreach ($File in $PSFiles) {
    $Errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $File.FullName -Raw), [ref]$Errors)
    
    if ($Errors.Count -gt 0) {
        Write-Host "  [FAIL] $($File.Name): Syntax errors found" -ForegroundColor Red
        $Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
        $ErrorCount++
    }
    else {
        Write-Host "  [PASS] $($File.Name)" -ForegroundColor Green
    }
}

# Test 2: Validate module structure
Write-Host "`n[TEST 2] Validating module structure..." -ForegroundColor Yellow

$ModulePath = Join-Path $ScriptRoot "Modules"
if (Test-Path $ModulePath) {
    $Modules = Get-ChildItem -Path $ModulePath -Filter "*.psm1"
    
    foreach ($Module in $Modules) {
        try {
            Import-Module $Module.FullName -Force -ErrorAction Stop
            Write-Host "  [PASS] $($Module.Name) loaded successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "  [FAIL] $($Module.Name): $($_.Exception.Message)" -ForegroundColor Red
            $ErrorCount++
        }
    }
    
    # Validate exported functions
    $RequiredFunctions = @(
        'Get-TenantEndpointConfiguration',
        'Test-TenantAccess',
        'Connect-MgGraphForTenant',
        'Get-AvailableConfigurations',
        'Import-IntuneConfiguration'
    )
    
    foreach ($Function in $RequiredFunctions) {
        if (Get-Command $Function -ErrorAction SilentlyContinue) {
            Write-Host "  [PASS] Function '$Function' is available" -ForegroundColor Green
        }
        else {
            Write-Host "  [FAIL] Function '$Function' not found" -ForegroundColor Red
            $ErrorCount++
        }
    }
}
else {
    Write-Host "  [FAIL] Modules directory not found" -ForegroundColor Red
    $ErrorCount++
}

# Test 3: Validate configuration files
Write-Host "`n[TEST 3] Validating configuration files..." -ForegroundColor Yellow

$ConfigPath = Join-Path $ScriptRoot "Configurations"
if (Test-Path $ConfigPath) {
    $JsonFiles = Get-ChildItem -Path $ConfigPath -Recurse -Filter "*.json" -File
    
    foreach ($JsonFile in $JsonFiles) {
        try {
            $Content = Get-Content $JsonFile.FullName -Raw | ConvertFrom-Json
            Write-Host "  [PASS] $($JsonFile.Name): Valid JSON" -ForegroundColor Green
            
            # Validate required properties
            if ($JsonFile.Name -like "*Compliance*" -or $JsonFile.Name -like "*Configuration*" -or $JsonFile.Name -like "*Baseline*") {
                if (-not $Content.displayName) {
                    Write-Host "  [WARN] $($JsonFile.Name): Missing displayName property" -ForegroundColor Yellow
                    $WarningCount++
                }
            }
        }
        catch {
            Write-Host "  [FAIL] $($JsonFile.Name): Invalid JSON - $($_.Exception.Message)" -ForegroundColor Red
            $ErrorCount++
        }
    }
}
else {
    Write-Host "  [WARN] Configurations directory not found" -ForegroundColor Yellow
    $WarningCount++
}

# Test 4: Validate tenant endpoint configurations
Write-Host "`n[TEST 4] Validating tenant endpoint configurations..." -ForegroundColor Yellow

$TenantTypes = @('Commercial', 'GCC', 'GCCHigh', 'DoD')
foreach ($TenantType in $TenantTypes) {
    try {
        $Config = Get-TenantEndpointConfiguration -TenantType $TenantType
        
        if ($Config -and $Config.GraphEndpoint -and $Config.LoginEndpoint) {
            Write-Host "  [PASS] $TenantType configuration valid" -ForegroundColor Green
        }
        else {
            Write-Host "  [FAIL] $TenantType configuration incomplete" -ForegroundColor Red
            $ErrorCount++
        }
    }
    catch {
        Write-Host "  [FAIL] $TenantType configuration error: $($_.Exception.Message)" -ForegroundColor Red
        $ErrorCount++
    }
}

# Test 5: Validate documentation files
Write-Host "`n[TEST 5] Validating documentation files..." -ForegroundColor Yellow

$RequiredDocs = @('README.md', 'QUICKSTART.md', 'EXAMPLES.md', 'SECURITY.md')
foreach ($Doc in $RequiredDocs) {
    $DocPath = Join-Path $ScriptRoot $Doc
    if (Test-Path $DocPath) {
        $Content = Get-Content $DocPath -Raw
        if ($Content.Length -gt 100) {
            Write-Host "  [PASS] $Doc exists and has content" -ForegroundColor Green
        }
        else {
            Write-Host "  [WARN] $Doc exists but appears empty" -ForegroundColor Yellow
            $WarningCount++
        }
    }
    else {
        Write-Host "  [FAIL] $Doc not found" -ForegroundColor Red
        $ErrorCount++
    }
}

# Test 6: Validate main script parameters
Write-Host "`n[TEST 6] Validating main script parameters..." -ForegroundColor Yellow

$MainScript = Join-Path $ScriptRoot "Start-IntuneHydration.ps1"
if (Test-Path $MainScript) {
    try {
        $AST = [System.Management.Automation.Language.Parser]::ParseFile($MainScript, [ref]$null, [ref]$null)
        $ParamBlock = $AST.ParamBlock
        
        if ($ParamBlock) {
            $Parameters = $ParamBlock.Parameters
            $RequiredParams = @('TenantType', 'TenantId')
            
            foreach ($Param in $RequiredParams) {
                $Found = $Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $Param }
                if ($Found) {
                    Write-Host "  [PASS] Parameter '$Param' found" -ForegroundColor Green
                }
                else {
                    Write-Host "  [FAIL] Parameter '$Param' not found" -ForegroundColor Red
                    $ErrorCount++
                }
            }
        }
        else {
            Write-Host "  [FAIL] No parameter block found in main script" -ForegroundColor Red
            $ErrorCount++
        }
    }
    catch {
        Write-Host "  [FAIL] Error parsing main script: $($_.Exception.Message)" -ForegroundColor Red
        $ErrorCount++
    }
}
else {
    Write-Host "  [FAIL] Main script not found" -ForegroundColor Red
    $ErrorCount++
}

# Test 7: Validate directory structure
Write-Host "`n[TEST 7] Validating directory structure..." -ForegroundColor Yellow

$RequiredDirs = @('Modules', 'Configurations', 'Configurations/CompliancePolicies', 'Configurations/DynamicGroups')
foreach ($Dir in $RequiredDirs) {
    $DirPath = Join-Path $ScriptRoot $Dir
    if (Test-Path $DirPath) {
        Write-Host "  [PASS] Directory '$Dir' exists" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] Directory '$Dir' not found" -ForegroundColor Yellow
        $WarningCount++
    }
}

# Test 8: Check for Microsoft.Graph module (informational)
Write-Host "`n[TEST 8] Checking for Microsoft.Graph PowerShell module..." -ForegroundColor Yellow

$MgGraphModule = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication
if ($MgGraphModule) {
    Write-Host "  [PASS] Microsoft.Graph.Authentication module is installed (Version: $($MgGraphModule[0].Version))" -ForegroundColor Green
}
else {
    Write-Host "  [INFO] Microsoft.Graph module not installed (required for actual use)" -ForegroundColor Cyan
    Write-Host "         Install with: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Cyan
}

# Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Errors: $ErrorCount" -ForegroundColor $(if ($ErrorCount -eq 0) { "Green" } else { "Red" })
Write-Host "Warnings: $WarningCount" -ForegroundColor $(if ($WarningCount -eq 0) { "Green" } else { "Yellow" })

if ($ErrorCount -eq 0) {
    Write-Host "`n[SUCCESS] All validation tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n[FAILURE] Validation completed with errors. Please review and fix." -ForegroundColor Red
    exit 1
}
