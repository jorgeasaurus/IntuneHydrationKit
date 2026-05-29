function Get-HydrationTenantDisplay {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$TenantId
    )

    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        return 'Discovered after sign-in'
    }

    Get-ObfuscatedTenantId -TenantId $TenantId
}
