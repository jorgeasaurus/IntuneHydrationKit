$maximumSignatureAgeDays = 7

if (-not (Get-Command -Name Get-MpComputerStatus -ErrorAction SilentlyContinue) -or
    -not (Get-Command -Name Update-MpSignature -ErrorAction SilentlyContinue)) {
    Write-Output 'Skipped: Microsoft Defender PowerShell cmdlets are not available.'
    exit 0
}

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
} catch {
    Write-Error 'Microsoft Defender status could not be queried.'
    exit 1
}

if (-not $status.AntivirusEnabled -or $status.AMRunningMode -ne 'Normal') {
    Write-Output 'Skipped: Microsoft Defender antivirus is not the active antivirus engine.'
    exit 0
}

try {
    Update-MpSignature -ErrorAction Stop | Out-Null
    $status = Get-MpComputerStatus -ErrorAction Stop
} catch {
    Write-Error 'Microsoft Defender signature update failed.'
    exit 1
}

if ($null -eq $status.AntivirusSignatureAge -or [int]$status.AntivirusSignatureAge -gt $maximumSignatureAgeDays) {
    Write-Error "Microsoft Defender signatures remain older than $maximumSignatureAgeDays day(s)."
    exit 1
}

Write-Output "Microsoft Defender signatures are current. AgeDays=$($status.AntivirusSignatureAge)"
exit 0
