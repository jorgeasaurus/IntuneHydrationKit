function Test-HydrationTuiArrowKeySupport {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not (Test-HydrationTuiHost)) {
        return $false
    }

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        return $false
    }

    if ($Host.Name -eq 'Windows PowerShell ISE Host') {
        return $false
    }

    try {
        $null = [Console]::KeyAvailable
        return $true
    } catch {
        return $false
    }
}
