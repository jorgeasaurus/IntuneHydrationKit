$minimumFreeSpaceGB = 10
$minimumCleanupSizeMB = 1024
$minimumAgeDays = 14
$cutoff = (Get-Date).AddDays(-$minimumAgeDays)

$systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$eligiblePaths = @($env:TEMP, (Join-Path -Path $env:WINDIR -ChildPath 'Temp')) | Select-Object -Unique
$eligibleSize = 0L

foreach ($path in $eligiblePaths) {
    if (Test-Path -LiteralPath $path) {
        $eligibleSize += [long](Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff -and -not $_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) } |
                Measure-Object -Property Length -Sum).Sum
    }
}

$freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
$eligibleSizeMB = [math]::Round($eligibleSize / 1MB, 2)
if ($freeSpaceGB -lt $minimumFreeSpaceGB -or $eligibleSizeMB -ge $minimumCleanupSizeMB) {
    Write-Output "Disk pressure detected: FreeSpaceGB=$freeSpaceGB; EligibleTempMB=$eligibleSizeMB"
    exit 1
}

Write-Output "Compliant: FreeSpaceGB=$freeSpaceGB; EligibleTempMB=$eligibleSizeMB"
exit 0
