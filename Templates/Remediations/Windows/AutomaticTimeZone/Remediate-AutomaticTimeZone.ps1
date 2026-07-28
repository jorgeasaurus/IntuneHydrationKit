$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='tzautoupdate'" -ErrorAction Stop
if ($service.StartMode -eq 'Disabled') {
    $process = Start-Process -FilePath "$env:SystemRoot\System32\sc.exe" -ArgumentList 'config', 'tzautoupdate', 'start=', 'demand' -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        Write-Error "Failed to enable the automatic time zone service. ExitCode=$($process.ExitCode)"
        exit 1
    }
}

try {
    Start-Service -Name 'tzautoupdate' -ErrorAction Stop
} catch {
    Write-Error 'Failed to start the automatic time zone service.'
    exit 1
}

Write-Output 'Automatic time zone service enabled. Location Services policy controls whether Windows can determine the time zone.'
exit 0
