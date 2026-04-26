function Get-HydrationGraphEnvironmentInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'Germany', 'China')]
        [string]$Environment
    )

    $endpoint = switch ($Environment) {
        'Global' { 'https://graph.microsoft.com' }
        'USGov' { 'https://graph.microsoft.us' }
        'USGovDoD' { 'https://dod-graph.microsoft.us' }
        'Germany' { 'https://graph.microsoft.de' }
        'China' { 'https://microsoftgraph.chinacloudapi.cn' }
    }

    return @{
        Environment = $Environment
        Endpoint    = $endpoint
    }
}
