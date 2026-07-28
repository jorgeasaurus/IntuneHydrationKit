$diskWarnings = @()
if (Get-Command -Name Get-PhysicalDisk -ErrorAction SilentlyContinue) {
    $diskWarnings = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.HealthStatus -notin @('Healthy', 'Unknown') })
}

$deviceErrors = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 })

if ($diskWarnings.Count -gt 0 -or $deviceErrors.Count -gt 0) {
    $diskNames = @($diskWarnings | Select-Object -First 3 -ExpandProperty FriendlyName) -join ', '
    $deviceNames = @($deviceErrors | Select-Object -First 3 -ExpandProperty Name) -join ', '
    Write-Output "Device health attention required: DiskWarnings=$($diskWarnings.Count) [$diskNames]; PnpErrors=$($deviceErrors.Count) [$deviceNames]"
    exit 1
}

Write-Output 'Compliant: no storage-health warnings or Plug and Play device errors found.'
exit 0
