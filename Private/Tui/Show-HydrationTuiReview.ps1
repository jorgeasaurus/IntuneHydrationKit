function Show-HydrationTuiReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    $selectedTargets = @(
        foreach ($option in Get-HydrationTuiImportOption) {
            if ($Settings.imports[$option.Key]) {
                $option.Label
            }
        }
    )

    $operation = if ($Settings.options.delete -and $Settings.options.dryRun) {
        'Dry-run delete'
    } elseif ($Settings.options.delete) {
        'Delete'
    } elseif ($Settings.options.dryRun) {
        'Dry-run create'
    } else {
        'Create'
    }

    Clear-HydrationTuiScreen
    $null = Show-HydrationTuiHeader
    $null = Show-HydrationTuiPanel -Title 'Review configuration' -Lines @(
        "Tenant ID: $(Get-HydrationTenantDisplay -TenantId $Settings.tenant.tenantId)"
        'Authentication: interactive'
        "Environment: $($Settings.authentication.environment)"
        "Operation: $operation"
        "Verbose: $($Settings.options.verbose)"
        "Platforms: $($Settings.platforms -join ', ')"
        "Targets: $($selectedTargets -join ', ')"
    )
}
