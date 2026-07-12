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

    $authorityHost = switch ($Environment) {
        'Global' { 'https://login.microsoftonline.com' }
        'USGov' { 'https://login.microsoftonline.us' }
        'USGovDoD' { 'https://login.microsoftonline.us' }
        'Germany' { 'https://login.microsoftonline.de' }
        'China' { 'https://login.chinacloudapi.cn' }
    }

    return @{
        Environment   = $Environment
        Endpoint      = $endpoint
        AuthorityHost = $authorityHost
    }
}
