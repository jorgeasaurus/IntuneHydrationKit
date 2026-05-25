function Test-HydrationGraphAccess {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$AccessChecks = @()
    )

    foreach ($accessCheck in @($AccessChecks)) {
        if ($null -eq $accessCheck -or [string]::IsNullOrWhiteSpace([string]$accessCheck.Uri)) {
            continue
        }

        try {
            $null = Invoke-HydrationGraphRequest -Method GET -Uri ([string]$accessCheck.Uri)
            Write-Verbose "Validated Graph access for $($accessCheck.Name)"
        } catch {
            $statusCode = Get-GraphStatusCode -ErrorRecord $_
            if ($statusCode -ne 401 -and $statusCode -ne 403) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Failed to validate Graph access for $($accessCheck.Name): $($_.Exception.Message)", $_.Exception),
                    'HydrationGraphAccessProbeFailed',
                    [System.Management.Automation.ErrorCategory]::ConnectionError,
                    $accessCheck
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            [PSCustomObject]@{
                Name       = [string]$accessCheck.Name
                Workload   = [string]$accessCheck.Workload
                StatusCode = $statusCode
            }
        }
    }
}
