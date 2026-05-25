function Remove-IntuneWinGetApps {
    <#
    .SYNOPSIS
        Removes WinGet hydration-owned Win32 apps that match the current template set.
    .DESCRIPTION
        Filters the supplied existing apps to those owned by the WinGet hydration importer
        and whose displayName is in the known template name set, then batch-deletes them.
        Supports WhatIf via the caller's ShouldProcess and WhatIfPreference state.
    .PARAMETER ExistingApps
        PSCustomObject with Items (array of app records) and Lookup (hashtable by name).
    .PARAMETER KnownTemplateNames
        HashSet of displayNames that are in scope for this operation.
    .PARAMETER PSCmdlet
        The calling cmdlet's $PSCmdlet so ShouldProcess decisions match the caller.
    .PARAMETER WhatIfPreference
        The caller's $WhatIfPreference value.
    .OUTPUTS
        PSCustomObject[] - Hydration results for each deleted or would-delete app.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [psobject]$ExistingApps,

        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]]$KnownTemplateNames,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$PSCmdlet,

        [Parameter()]
        [bool]$WhatIfPreference = $false
    )

    $appsToDelete = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($existingApp in $ExistingApps.Items) {
        if (-not $existingApp.IsOwned) {
            continue
        }

        if (-not $KnownTemplateNames.Contains($existingApp.DisplayName)) {
            Write-Verbose "Skipping '$($existingApp.DisplayName)' - not in current WinGet templates"
            Write-Debug "Delete decision: skipping '$($existingApp.DisplayName)' because it is WinGet-owned but not in the current template set."
            continue
        }

        Write-Debug "Delete decision: queued '$($existingApp.DisplayName)' (AppId='$($existingApp.Id)') for deletion."
        $appsToDelete.Add(@{
                Name = $existingApp.DisplayName
                Id   = $existingApp.Id
                Url  = "/deviceAppManagement/mobileApps/$($existingApp.Id)"
            })
    }

    if ($appsToDelete.Count -eq 0) {
        Write-Verbose 'No WinGet hydration-owned apps found to delete'
        return @()
    }

    $results = @()

    if (-not $PSCmdlet.ShouldProcess("$($appsToDelete.Count) WinGet Win32 app(s)", 'Delete')) {
        if ($WhatIfPreference) {
            foreach ($app in $appsToDelete) {
                $results += Add-HydrationDryRunResult -Action 'WouldDelete' -Name $app.Name -Type 'WinGetWin32App'
            }
        }

        return $results
    }

    $appNames = (@($appsToDelete.Name)) -join "', '"
    Write-Debug "Deleting $($appsToDelete.Count) WinGet-owned app(s): '$appNames'."
    $results += Invoke-GraphBatchOperation -Items @($appsToDelete) -Operation 'DELETE' -ResultType 'WinGetWin32App'
    return $results
}
