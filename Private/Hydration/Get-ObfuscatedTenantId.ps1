function Get-ObfuscatedTenantId {
    <#
    .SYNOPSIS
        Obfuscates a tenant ID for safe logging
    .DESCRIPTION
        Returns an obfuscated version of the tenant ID to prevent sensitive data exposure in logs.
        GUID format: Shows first 8 and last 12 characters with middle masked
        Domain format: Shows first 4 characters with rest masked
    .PARAMETER TenantId
        The tenant ID to obfuscate (GUID or domain name)
    .EXAMPLE
        Get-ObfuscatedTenantId -TenantId "12345678-1234-1234-1234-123456789abc"
        # Returns: 12345678****-****-****-123456789abc
    .EXAMPLE
        Get-ObfuscatedTenantId -TenantId "contoso.onmicrosoft.com"
        # Returns: cont***
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )

    if ($TenantId -match '^[a-f0-9-]{36}$') {
        return "$($TenantId.Substring(0,8))****-****-****-$($TenantId.Substring(24))"
    } else {
        return "$($TenantId.Substring(0, [Math]::Min(4, $TenantId.Length)))***"
    }
}
