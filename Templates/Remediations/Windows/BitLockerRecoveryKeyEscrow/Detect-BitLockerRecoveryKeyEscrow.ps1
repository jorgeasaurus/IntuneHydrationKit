$cloudJoinPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'

if (-not (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue) -or
    -not (Test-Path -LiteralPath $cloudJoinPath)) {
    Write-Output 'Skipped: BitLocker or Microsoft Entra join prerequisites are not present.'
    exit 0
}

try {
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
} catch {
    Write-Output 'Skipped: the operating system BitLocker volume could not be queried.'
    exit 0
}

if ($volume.ProtectionStatus -notin @('On', 1)) {
    Write-Output 'Skipped: BitLocker protection is not active on the operating system volume.'
    exit 0
}

$recoveryProtectors = @($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
if ($recoveryProtectors.Count -eq 0) {
    Write-Output 'Skipped: no BitLocker recovery-password protector is configured.'
    exit 0
}

Write-Output "Recovery key escrow retry required for $($recoveryProtectors.Count) existing protector(s)."
exit 1
