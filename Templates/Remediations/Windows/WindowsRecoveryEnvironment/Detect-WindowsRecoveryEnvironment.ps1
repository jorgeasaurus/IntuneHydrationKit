$reAgentPath = Join-Path -Path $env:WINDIR -ChildPath 'System32\Recovery\ReAgent.xml'
$localWinReImagePath = Join-Path -Path $env:WINDIR -ChildPath 'System32\Recovery\Winre.wim'

if (-not (Test-Path -LiteralPath $reAgentPath) -or -not (Test-Path -LiteralPath $localWinReImagePath)) {
    Write-Output 'Skipped: no locally repairable Windows Recovery Environment configuration was found.'
    exit 0
}

try {
    [xml]$reAgentConfiguration = Get-Content -LiteralPath $reAgentPath -Raw -ErrorAction Stop
    $winReBcdId = [string]$reAgentConfiguration.WindowsRE.WinreBCD.id
} catch {
    Write-Output 'Skipped: Windows Recovery Environment configuration could not be read.'
    exit 0
}

if ($winReBcdId -match '^\{?00000000-0000-0000-0000-000000000000\}?$') {
    Write-Output 'Windows Recovery Environment is explicitly disabled and has a local recovery image.'
    exit 1
}

if ($winReBcdId -match '^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$') {
    Write-Output 'Compliant: Windows Recovery Environment has a configured BCD identifier.'
    exit 0
}

Write-Output 'Skipped: Windows Recovery Environment state could not be determined safely.'
exit 0
