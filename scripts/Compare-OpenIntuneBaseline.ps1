<#
.SYNOPSIS
    Compares bundled OpenIntuneBaseline templates against the upstream repository.
.DESCRIPTION
    Downloads the latest OpenIntuneBaseline from the upstream SkipToTheEndpoint GitHub repository
    and compares it against the bundled templates in Templates/OpenIntuneBaseline/.

    Reports:
    - Files only in upstream (new policies you may want to add)
    - Files only in local bundle (removed or renamed upstream)
    - Files with content differences (modified policies)

    NativeImport directories are excluded as they duplicate IntuneManagement content.
    Non-JSON files (README, CHANGELOG, CSV, etc.) are excluded from comparison.
.PARAMETER UpstreamRepoUrl
    GitHub repository URL for the upstream baseline.
    Default: https://github.com/SkipToTheEndpoint/OpenIntuneBaseline
.PARAMETER Branch
    Branch to compare against. Default: main
.PARAMETER LocalPath
    Path to local bundled templates. Default: Templates/OpenIntuneBaseline relative to repo root.
.PARAMETER KeepDownload
    If specified, the downloaded upstream files are not cleaned up after comparison.
.EXAMPLE
    ./scripts/Compare-OpenIntuneBaseline.ps1
    # Compare bundled templates against upstream SkipToTheEndpoint repo

.EXAMPLE
    ./scripts/Compare-OpenIntuneBaseline.ps1 -UpstreamRepoUrl "https://github.com/skiptotheendpoint/OpenIntuneBaseline"
    # Compare against the maintained fork instead

.EXAMPLE
    ./scripts/Compare-OpenIntuneBaseline.ps1 -KeepDownload
    # Keep the downloaded upstream files for manual inspection
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$UpstreamRepoUrl = "https://github.com/SkipToTheEndpoint/OpenIntuneBaseline",

    [Parameter()]
    [string]$Branch = "main",

    [Parameter()]
    [string]$LocalPath,

    [Parameter()]
    [switch]$KeepDownload
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Resolve paths
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $LocalPath) {
    $LocalPath = Join-Path -Path $repoRoot -ChildPath (Join-Path -Path 'Templates' -ChildPath 'OpenIntuneBaseline')
}

if (-not (Test-Path -Path $LocalPath)) {
    Write-Error "Local template path not found: $LocalPath"
    return
}

# Directories to exclude from comparison (duplicates of IntuneManagement content)
$excludedPatterns = @(
    'NativeImport'
    'Scripts'
)

# File extensions to compare (only JSON policy files)
$includeExtension = '.json'

# --- Download upstream ---
$repoName = ($UpstreamRepoUrl -split '/')[-1]
$repoOwner = ($UpstreamRepoUrl -split '/')[-2]
$zipUrl = "$UpstreamRepoUrl/archive/refs/heads/$Branch.zip"
$tempBase = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OIB-Compare-$(Get-Random)"
$zipPath = Join-Path -Path $tempBase -ChildPath "$repoName-$Branch.zip"
$extractPath = Join-Path -Path $tempBase -ChildPath 'upstream'

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       OpenIntuneBaseline Parity Check                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Upstream : $repoOwner/$repoName ($Branch)" -ForegroundColor Gray
Write-Host "  Local    : $LocalPath" -ForegroundColor Gray
Write-Host ""

try {
    $null = New-Item -Path $tempBase -ItemType Directory -Force

    Write-Host "  Downloading upstream baseline..." -ForegroundColor Yellow -NoNewline
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
    Write-Host " Done" -ForegroundColor Green

    Write-Host "  Extracting..." -ForegroundColor Yellow -NoNewline
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    Write-Host " Done" -ForegroundColor Green

    # GitHub archives extract to a subfolder like OpenIntuneBaseline-main/
    $extractedFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
    if (-not $extractedFolder) {
        Write-Error "Failed to find extracted upstream folder in $extractPath"
        return
    }
    $upstreamRoot = $extractedFolder.FullName

    # --- Collect files ---

    # Helper: get relative JSON paths, excluding unwanted directories
    function Get-PolicyFiles {
        param(
            [string]$BasePath
        )
        $allFiles = Get-ChildItem -Path $BasePath -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue
        $results = @{}
        foreach ($file in $allFiles) {
            $relativePath = $file.FullName.Substring($BasePath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, '/', '\')
            # Normalize to forward slashes for cross-platform consistency
            $relativePath = $relativePath -replace '\\', '/'

            # Check exclusions
            $excluded = $false
            foreach ($pattern in $excludedPatterns) {
                if ($relativePath -match "(^|/)$pattern(/|$)") {
                    $excluded = $true
                    break
                }
            }

            if (-not $excluded) {
                $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
                $results[$relativePath] = @{
                    FullPath = $file.FullName
                    Hash     = $hash
                    Size     = $file.Length
                }
            }
        }
        return $results
    }

    Write-Host "  Scanning files..." -ForegroundColor Yellow -NoNewline
    $upstreamFiles = Get-PolicyFiles -BasePath $upstreamRoot
    $localFiles = Get-PolicyFiles -BasePath $LocalPath
    Write-Host " Done" -ForegroundColor Green
    Write-Host ""

    # --- Compare ---
    $onlyUpstream = [System.Collections.Generic.List[string]]::new()
    $onlyLocal = [System.Collections.Generic.List[string]]::new()
    $modified = [System.Collections.Generic.List[string]]::new()
    $matched = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $upstreamFiles.Keys) {
        if ($localFiles.ContainsKey($key)) {
            if ($upstreamFiles[$key].Hash -ne $localFiles[$key].Hash) {
                $modified.Add($key)
            } else {
                $matched.Add($key)
            }
        } else {
            $onlyUpstream.Add($key)
        }
    }

    foreach ($key in $localFiles.Keys) {
        if (-not $upstreamFiles.ContainsKey($key)) {
            $onlyLocal.Add($key)
        }
    }

    # --- Report ---
    $totalUpstream = $upstreamFiles.Count
    $totalLocal = $localFiles.Count

    Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  RESULTS" -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Upstream files (JSON, excl. NativeImport) : $totalUpstream" -ForegroundColor Gray
    Write-Host "  Local bundled files                       : $totalLocal" -ForegroundColor Gray
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Identical                                 : $($matched.Count)" -ForegroundColor Green
    Write-Host "  Modified (content differs)                : $($modified.Count)" -ForegroundColor $(if ($modified.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  Only in upstream (missing locally)        : $($onlyUpstream.Count)" -ForegroundColor $(if ($onlyUpstream.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Only in local (not in upstream)           : $($onlyLocal.Count)" -ForegroundColor $(if ($onlyLocal.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ""

    if ($modified.Count -gt 0) {
        Write-Host "  ⚠ MODIFIED FILES (content differs from upstream):" -ForegroundColor Yellow
        foreach ($file in ($modified | Sort-Object)) {
            Write-Host "    ∆ $file" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if ($onlyUpstream.Count -gt 0) {
        Write-Host "  ✗ MISSING FROM LOCAL (new in upstream, consider adding):" -ForegroundColor Red
        foreach ($file in ($onlyUpstream | Sort-Object)) {
            Write-Host "    + $file" -ForegroundColor Red
        }
        Write-Host ""
    }

    if ($onlyLocal.Count -gt 0) {
        Write-Host "  ◦ ONLY IN LOCAL (not found upstream, may be custom or renamed):" -ForegroundColor DarkYellow
        foreach ($file in ($onlyLocal | Sort-Object)) {
            Write-Host "    - $file" -ForegroundColor DarkYellow
        }
        Write-Host ""
    }

    # Final verdict
    if ($modified.Count -eq 0 -and $onlyUpstream.Count -eq 0 -and $onlyLocal.Count -eq 0) {
        Write-Host "  ✓ PARITY CHECK PASSED — local templates match upstream exactly." -ForegroundColor Green
    } else {
        $issueCount = $modified.Count + $onlyUpstream.Count + $onlyLocal.Count
        Write-Host "  ✗ PARITY CHECK: $issueCount difference(s) found." -ForegroundColor Red
        Write-Host "    Review the items above and update Templates/OpenIntuneBaseline as needed." -ForegroundColor Gray
    }
    Write-Host ""

} catch {
    Write-Error "Comparison failed: $_"
} finally {
    if (-not $KeepDownload -and (Test-Path -Path $tempBase -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue *>$null
        Write-Host "  Cleaned up temporary files." -ForegroundColor DarkGray
    } elseif ($KeepDownload -and (Test-Path -Path $tempBase -ErrorAction SilentlyContinue)) {
        Write-Host "  Upstream files kept at: $tempBase" -ForegroundColor DarkGray
    }
}
