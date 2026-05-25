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

$publicFunctions = Get-ChildItem -Path $publicPath -Filter '*.ps1' -File -Recurse |
    Sort-Object -Property BaseName |
    ForEach-Object { $_.BaseName }

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

if ($newManifestContent -eq $manifestContent -and $newModuleContent -eq $moduleContent) {
    Write-Host 'Public function exports are already in sync.'
    return
}

if ($CheckOnly) {
    Write-Host 'Public function exports are out of sync. Run scripts/Sync-PublicFunctionExports.ps1 to apply updates.'
    exit 1
}

if ($PSCmdlet.ShouldProcess($manifestPath, 'Update FunctionsToExport list') -and
    $PSCmdlet.ShouldProcess($modulePath, 'Update $publicFunctions export list')) {
    Set-Content -Path $manifestPath -Value $newManifestContent -Encoding utf8
    Set-Content -Path $modulePath -Value $newModuleContent -Encoding utf8
    Write-Host 'Updated IntuneHydrationKit.psd1 and IntuneHydrationKit.psm1 from Public/**/*.ps1.'
}
