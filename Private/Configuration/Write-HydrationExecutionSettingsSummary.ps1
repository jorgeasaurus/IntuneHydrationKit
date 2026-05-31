function Write-HydrationExecutionSettingsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    $summaryLines = @(
        (Format-HydrationDisplayMessage -Message "Target Tenant: $(Get-HydrationTenantDisplay -TenantId $Settings.tenant.tenantId)" -Style 'Info' -Emoji '🎯')
    )

    if ($Settings.tenant.tenantName) {
        $summaryLines += Format-HydrationDisplayMessage -Message "Tenant Name: $($Settings.tenant.tenantName)" -Style 'Info' -Emoji '🏢'
    }

    $summaryLines += @(
        (Format-HydrationDisplayMessage -Message "Authentication Mode: $($Settings.authentication.mode)" -Style 'Info' -Emoji '🔐')
        (Format-HydrationDisplayMessage -Message 'Options:' -Style 'Section' -Emoji '⚙️')
        (Format-HydrationDisplayMessage -Message (($Settings.options | Out-String).TrimEnd()) -Style 'Muted')
        (Format-HydrationDisplayMessage -Message 'Imports Enabled:' -Style 'Section' -Emoji '📦')
        (Format-HydrationDisplayMessage -Message (($Settings.imports | Out-String).TrimEnd()) -Style 'Muted')
        (Format-HydrationDisplayMessage -Message "Platform Filter: $($Settings.platforms -join ', ')" -Style 'Info' -Emoji '🧭')
    )

    foreach ($summaryLine in $summaryLines) {
        Write-Information $summaryLine -InformationAction Continue
    }
}
