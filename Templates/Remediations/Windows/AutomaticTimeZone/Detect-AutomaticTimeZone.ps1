$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='tzautoupdate'" -ErrorAction Stop
if ($service.StartMode -eq 'Disabled') {
    Write-Output 'Automatic time zone service is disabled.'
    exit 1
}

Write-Output "Compliant: automatic time zone service start mode is $($service.StartMode)."
exit 0
