function Get-AppProtectionEndpointInfo {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')]
        [string[]]$Platform = @('All')
    )

    $endpointInfo = @(
        @{
            Platform  = 'iOS'
            ODataType = '#microsoft.graph.iosManagedAppProtection'
            Endpoint  = 'beta/deviceAppManagement/iosManagedAppProtections'
        }
        @{
            Platform  = 'Android'
            ODataType = '#microsoft.graph.androidManagedAppProtection'
            Endpoint  = 'beta/deviceAppManagement/androidManagedAppProtections'
        }
    )

    if (-not $Platform -or $Platform -contains 'All') {
        return $endpointInfo
    }

    return @($endpointInfo | Where-Object { $Platform -contains $_.Platform })
}
