#Requires -Version 7.0

<#
.SYNOPSIS
    Bootstrap script for IntuneHydrationKit build process
.DESCRIPTION
    Installs required build dependencies (InvokeBuild, Pester, PSScriptAnalyzer)
    and optionally invokes the build process.
.PARAMETER Task
    The build task(s) to run. If not specified, only bootstraps dependencies.
.PARAMETER NoBuild
    Only install dependencies, don't run any build tasks.
.EXAMPLE
    ./build.ps1
    Installs dependencies only.
.EXAMPLE
    ./build.ps1 -Task Build
    Installs dependencies and runs the Build task.
.EXAMPLE
    ./build.ps1 -Task Analyze, Test, Build
    Installs dependencies and runs multiple tasks.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Task,

    [Parameter()]
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

Write-Information "=== IntuneHydrationKit Build Bootstrap ==="

# Required modules for build process
$requiredModules = @(
    @{ Name = 'InvokeBuild'; MinimumVersion = '5.10.0' }
    @{ Name = 'Pester'; MinimumVersion = '5.4.0' }
    @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.21.0' }
)

# Install/update required modules
foreach ($module in $requiredModules) {
    $installed = Get-Module -Name $module.Name -ListAvailable |
        Where-Object { $_.Version -ge [version]$module.MinimumVersion } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $installed) {
        Write-Information "Installing $($module.Name) >= $($module.MinimumVersion)..."
        Install-Module -Name $module.Name -MinimumVersion $module.MinimumVersion -Force -Scope CurrentUser -AllowClobber
        Write-Information "  Installed $($module.Name)"
    } else {
        Write-Information "Found $($module.Name) v$($installed.Version)"
    }
}

Write-Information "Bootstrap complete."

# Run build if tasks specified and not NoBuild
if ($Task -and -not $NoBuild) {
    Write-Information ""
    Write-Information "Running build tasks: $($Task -join ', ')"

    $buildScript = Join-Path -Path $PSScriptRoot -ChildPath 'IntuneHydrationKit.build.ps1'
    if (-not (Test-Path $buildScript)) {
        throw "Build script not found: $buildScript"
    }

    Import-Module InvokeBuild -Force
    Invoke-Build -File $buildScript -Task $Task
}
