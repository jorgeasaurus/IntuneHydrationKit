$cloudJoinPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'

if (-not (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue) -or
    -not (Test-Path -LiteralPath $cloudJoinPath)) {
    Write-Output 'Skipped: BitLocker or Microsoft Entra join prerequisites are not present.'
    exit 0
}

try {
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
} catch {
    Write-Error 'The operating system BitLocker volume could not be queried.'
    exit 1
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

$backupFailures = 0
foreach ($protector in $recoveryProtectors) {
    try {
        BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $protector.KeyProtectorId -ErrorAction Stop
    } catch {
        $backupFailures++
    }
}

if ($backupFailures -gt 0) {
    Write-Error "Microsoft Entra recovery-key escrow failed for $backupFailures protector(s)."
    exit 1
}

Write-Output "Microsoft Entra recovery-key escrow completed for $($recoveryProtectors.Count) existing protector(s)."
exit 0
