$maximumSignatureAgeDays = 7

if (-not (Get-Command -Name Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
    Write-Output 'Skipped: Microsoft Defender PowerShell cmdlets are not available.'
    exit 0
}

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
} catch {
    Write-Output 'Skipped: Microsoft Defender status could not be queried.'
    exit 0
}

if (-not $status.AntivirusEnabled -or $status.AMRunningMode -ne 'Normal') {
    Write-Output 'Skipped: Microsoft Defender antivirus is not the active antivirus engine.'
    exit 0
}

if ($null -eq $status.AntivirusSignatureAge -or [int]$status.AntivirusSignatureAge -gt $maximumSignatureAgeDays) {
    Write-Output "Microsoft Defender signatures are stale or unavailable. MaximumAgeDays=$maximumSignatureAgeDays"
    exit 1
}

Write-Output "Compliant: Microsoft Defender signature age is $($status.AntivirusSignatureAge) day(s)."
exit 0
