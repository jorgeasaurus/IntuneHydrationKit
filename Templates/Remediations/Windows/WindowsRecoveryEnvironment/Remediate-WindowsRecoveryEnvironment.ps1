$reAgentPath = Join-Path -Path $env:WINDIR -ChildPath 'System32\Recovery\ReAgent.xml'
$localWinReImagePath = Join-Path -Path $env:WINDIR -ChildPath 'System32\Recovery\Winre.wim'
$reAgentExecutable = Join-Path -Path $env:WINDIR -ChildPath 'System32\reagentc.exe'

if (-not (Test-Path -LiteralPath $reAgentPath) -or
    -not (Test-Path -LiteralPath $localWinReImagePath) -or
    -not (Test-Path -LiteralPath $reAgentExecutable)) {
    Write-Output 'Skipped: no locally repairable Windows Recovery Environment configuration was found.'
    exit 0
}

try {
    [xml]$reAgentConfiguration = Get-Content -LiteralPath $reAgentPath -Raw -ErrorAction Stop
    $winReBcdId = [string]$reAgentConfiguration.WindowsRE.WinreBCD.id
} catch {
    Write-Error 'Windows Recovery Environment configuration could not be read.'
    exit 1
}

if ($winReBcdId -notmatch '^\{?00000000-0000-0000-0000-000000000000\}?$') {
    Write-Output 'Skipped: Windows Recovery Environment is not explicitly disabled.'
    exit 0
}

& $reAgentExecutable /enable
if ($LASTEXITCODE -ne 0) {
    Write-Error "Windows Recovery Environment enablement failed. ExitCode=$LASTEXITCODE"
    exit 1
}

try {
    [xml]$reAgentConfiguration = Get-Content -LiteralPath $reAgentPath -Raw -ErrorAction Stop
    $winReBcdId = [string]$reAgentConfiguration.WindowsRE.WinreBCD.id
} catch {
    Write-Error 'Windows Recovery Environment configuration could not be verified.'
    exit 1
}

if ($winReBcdId -notmatch '^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$' -or
    $winReBcdId -match '^\{?00000000-0000-0000-0000-000000000000\}?$') {
    Write-Error 'Windows Recovery Environment remained disabled after enablement.'
    exit 1
}

Write-Output 'Windows Recovery Environment enabled using the existing local recovery image.'
exit 0
