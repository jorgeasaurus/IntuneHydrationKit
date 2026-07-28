$minimumFreeSpaceGB = 10
$minimumAgeDays = 14
$maximumCleanupMB = 4096
$cutoff = (Get-Date).AddDays(-$minimumAgeDays)
$maximumCleanupBytes = $maximumCleanupMB * 1MB
$removedBytes = 0L

$eligiblePaths = @($env:TEMP, (Join-Path -Path $env:WINDIR -ChildPath 'Temp')) | Select-Object -Unique
foreach ($path in $eligiblePaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    $files = Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff -and -not $_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) } |
        Sort-Object LastWriteTime

    foreach ($file in $files) {
        if ($removedBytes -ge $maximumCleanupBytes) {
            break
        }

        try {
            $fileLength = $file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removedBytes += $fileLength
        } catch {
            continue
        }
    }
}

$systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
$removedMB = [math]::Round($removedBytes / 1MB, 2)
Write-Output "Disk cleanup completed: RemovedMB=$removedMB; FreeSpaceGB=$freeSpaceGB; TargetFreeSpaceGB=$minimumFreeSpaceGB"
exit 0
