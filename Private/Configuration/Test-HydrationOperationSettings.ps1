function Test-HydrationOperationSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$CreateEnabled,

        [Parameter(Mandatory)]
        [bool]$DeleteEnabled,

        [Parameter(Mandatory)]
        [bool]$ForceDelete,

        [Parameter(Mandatory)]
        [bool]$WhatIfEnabled,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$PSCmdlet
    )

    if ($CreateEnabled -and $DeleteEnabled) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Only one of 'create' or 'delete' options can be true. Current settings: create=$CreateEnabled, delete=$DeleteEnabled"),
            'MutuallyExclusiveOptions',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if (-not $CreateEnabled -and -not $DeleteEnabled) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("At least one of 'create' or 'delete' options must be true. Current settings: create=$CreateEnabled, delete=$DeleteEnabled"),
            'NoOperationSelected',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($DeleteEnabled -and -not $ForceDelete -and -not $WhatIfEnabled) {
        if (-not $PSCmdlet.ShouldContinue("Proceed with delete operations?", "Delete mode will remove Intune configurations created by the hydration kit.")) {
            Write-Warning "Delete operation cancelled by user confirmation."
            return $false
        }
    }

    return $true
}
