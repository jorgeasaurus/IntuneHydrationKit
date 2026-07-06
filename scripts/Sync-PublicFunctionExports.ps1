#Requires -Version 7.0

<#
.SYNOPSIS
    Synchronises the public-function export lists in the module manifest and root module file.

.DESCRIPTION
    Scans every *.ps1 file under Public/ and updates the FunctionsToExport array in
    IntuneHydrationKit.psd1 and the $publicFunctions array in IntuneHydrationKit.psm1 to
    match. Run this after adding or removing a public function to keep the manifest and
    module file in sync.

.PARAMETER CheckOnly
    When specified, reports whether exports are out of sync and exits with code 1 if they
    are, without making any changes. Useful in CI to catch forgotten sync runs.

.EXAMPLE
    ./scripts/Sync-PublicFunctionExports.ps1
    Updates both IntuneHydrationKit.psd1 and IntuneHydrationKit.psm1 to reflect the
    current contents of Public/**/*.ps1.

.EXAMPLE
    ./scripts/Sync-PublicFunctionExports.ps1 -CheckOnly
    Exits with code 1 and prints a message if the export lists are stale; makes no changes.

.EXAMPLE
    ./scripts/Sync-PublicFunctionExports.ps1 -WhatIf
    Shows what would be changed without writing to disk.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$CheckOnly
)

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$publicPath = Join-Path -Path $repoRoot -ChildPath 'Public'
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'IntuneHydrationKit.psd1'
$modulePath = Join-Path -Path $repoRoot -ChildPath 'IntuneHydrationKit.psm1'

if (-not (Test-Path -Path $publicPath -PathType Container)) {
    throw "Public function directory not found: $publicPath"
}

$intentionalHelperExports = @(
    'New-HydrationResult'
    'Get-ResultSummary'
    'Get-GraphErrorMessage'
    'Test-HydrationKitObject'
    'Get-ObfuscatedTenantId'
)

$publicFunctions = @(
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -File -Recurse |
    Sort-Object -Property BaseName |
    ForEach-Object { $_.BaseName }
    $intentionalHelperExports
) | Sort-Object -Unique

if ($publicFunctions.Count -eq 0) {
    throw 'No public function files were found under Public/.'
}

$functionListText = ($publicFunctions | ForEach-Object { "        '$_'" }) -join ",`n"

$manifestContent = Get-Content -Path $manifestPath -Raw -Encoding utf8
$moduleContent = Get-Content -Path $modulePath -Raw -Encoding utf8

$manifestPattern = 'FunctionsToExport\s*=\s*@\((?s:.*?)\)\s*\r?\n\s*\r?\n\s*# Cmdlets to export from this module'
$manifestReplacement = @"
FunctionsToExport = @(
$functionListText
    )

    # Cmdlets to export from this module
"@

$modulePattern = '\$publicFunctions\s*=\s*@\((?s:.*?)\)\s*\r?\n\s*\r?\n# Export functions'
$moduleReplacement = @"
`$publicFunctions = @(
$functionListText
)

# Export functions
"@

if (-not [regex]::IsMatch($manifestContent, $manifestPattern)) {
    throw "Could not locate FunctionsToExport block in module manifest: $manifestPath"
}

if (-not [regex]::IsMatch($moduleContent, $modulePattern)) {
    throw "Could not locate publicFunctions export block in module file: $modulePath"
}

$newManifestContent = [regex]::Replace($manifestContent, $manifestPattern, $manifestReplacement)
$newModuleContent = [regex]::Replace($moduleContent, $modulePattern, $moduleReplacement)
$newManifestContent = $newManifestContent.TrimEnd() + [Environment]::NewLine
$newModuleContent = $newModuleContent.TrimEnd() + [Environment]::NewLine

if ($newManifestContent -eq $manifestContent -and $newModuleContent -eq $moduleContent) {
    Write-Information 'Public function exports are already in sync.' -InformationAction Continue
    return
}

if ($CheckOnly) {
    Write-Information 'Public function exports are out of sync. Run scripts/Sync-PublicFunctionExports.ps1 to apply updates.' -InformationAction Continue
    exit 1
}

if ($PSCmdlet.ShouldProcess($manifestPath, 'Update FunctionsToExport list') -and
    $PSCmdlet.ShouldProcess($modulePath, 'Update $publicFunctions export list')) {
    # -NoNewline keeps the write byte-identical to the compared string (idempotent check)
    Set-Content -Path $manifestPath -Value $newManifestContent -Encoding utf8 -NoNewline
    Set-Content -Path $modulePath -Value $newModuleContent -Encoding utf8 -NoNewline
    Write-Information 'Updated IntuneHydrationKit.psd1 and IntuneHydrationKit.psm1 from Public/**/*.ps1.' -InformationAction Continue
}
