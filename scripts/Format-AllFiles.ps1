<#
.SYNOPSIS
    Formats all PowerShell files in the repository using PSScriptAnalyzer.
.DESCRIPTION
    Uses Invoke-Formatter with OTBS (One True Brace Style) settings to format
    all .ps1 and .psm1 files, excluding the build directory.
#>
[CmdletBinding()]
param()

$files = Get-ChildItem -Path $PSScriptRoot/.. -Include *.ps1, *.psm1 -Recurse -File |
    Where-Object { $_.DirectoryName -notlike '*build*' }

Write-Information "Formatting $($files.Count) PowerShell files..." -ForegroundColor Cyan

foreach ($file in $files) {
    try {
        $content = Get-Content $file.FullName -Raw
        $formatted = Invoke-Formatter -ScriptDefinition $content -Settings CodeFormattingOTBS
        Set-Content -Path $file.FullName -Value $formatted -NoNewline
        Write-Information "  Formatted: $($file.Name)" -ForegroundColor Green
    } catch {
        Write-Information "  Failed: $($file.Name) - $_" -ForegroundColor Red
    }
}

Write-Information "Done!" -ForegroundColor Cyan
