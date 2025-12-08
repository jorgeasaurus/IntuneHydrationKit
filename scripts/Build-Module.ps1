#Requires -Version 7.0

<#
.SYNOPSIS
    Local equivalent of the Build Module GitHub workflow.
.DESCRIPTION
    Runs PSScriptAnalyzer, Pester tests, and builds the module locally.
    This is the PowerShell equivalent of .github/workflows/Build Module.yml
.EXAMPLE
    ./scripts/Build-Module.ps1
    Runs the full build pipeline (analyze, test, build).
.EXAMPLE
    ./scripts/Build-Module.ps1 -SkipTests
    Runs analyze and build, skipping tests.
.EXAMPLE
    ./scripts/Build-Module.ps1 -TaskOnly Analyze
    Runs only the specified task.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipTests,

    [Parameter()]
    [ValidateSet('Analyze', 'Test', 'Build', 'Clean')]
    [string]$TaskOnly
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Navigate to repository root
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    Write-Information "=== Build Module (Local) ==="
    Write-Information "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Information "Working Directory: $PWD"
    Write-Information ""

    # Bootstrap dependencies
    Write-Information "=== Bootstrapping Dependencies ==="
    & ./build.ps1
    Write-Information ""

    # Import InvokeBuild
    Import-Module InvokeBuild -Force

    # Determine tasks to run
    if ($TaskOnly) {
        $tasks = @($TaskOnly)
    } elseif ($SkipTests) {
        $tasks = @('Analyze', 'Build')
    } else {
        $tasks = @('Analyze', 'Test', 'Build')
    }

    foreach ($task in $tasks) {
        Write-Information "=== Running Task: $task ==="
        Invoke-Build -File ./IntuneHydrationKit.build.ps1 -Task $task
        Write-Information ""
    }

    Write-Information "=== Build Complete ==="

    # Show build artifacts location
    $buildPath = Join-Path $repoRoot 'build' 'IntuneHydrationKit'
    if (Test-Path $buildPath) {
        Write-Information "Build artifacts: $buildPath"
        Get-ChildItem $buildPath | ForEach-Object {
            Write-Information "  $($_.Name)"
        }
    }

} finally {
    Pop-Location
}
