function Set-HydrationConnectionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'Germany', 'China')]
        [string]$Environment
    )

    $environmentInfo = Get-HydrationGraphEnvironmentInfo -Environment $Environment
    $script:GraphEnvironment = $environmentInfo.Environment
    $script:GraphEndpoint = $environmentInfo.Endpoint
    $script:HydrationState.Connected = $true
    $script:HydrationState.TenantId = $TenantId
    $script:HydrationState.Environment = $Environment

    return $environmentInfo
}
