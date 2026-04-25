function Write-HydrationExecutionSettingsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    $summaryLines = @(
        "Target Tenant: $(Get-ObfuscatedTenantId -TenantId $Settings.tenant.tenantId)"
    )

    if ($Settings.tenant.tenantName) {
        $summaryLines += "Tenant Name: $($Settings.tenant.tenantName)"
    }

    $summaryLines += @(
        "Authentication Mode: $($Settings.authentication.mode)"
        'Options:'
        ($Settings.options | Out-String).TrimEnd()
        'Imports Enabled:'
        ($Settings.imports | Out-String).TrimEnd()
        "Platform Filter: $($Settings.platforms -join ', ')"
    )

    foreach ($summaryLine in $summaryLines) {
        Write-Information $summaryLine -InformationAction Continue
    }
}
