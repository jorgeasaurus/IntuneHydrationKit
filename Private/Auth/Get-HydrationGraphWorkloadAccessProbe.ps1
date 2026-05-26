function Get-HydrationGraphWorkloadAccessProbe {
    <#
    .SYNOPSIS
        Builds the selected Graph workload access probes for pre-flight validation.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Imports,

        [Parameter()]
        [hashtable]$MobileAppConfiguration = @{},

        [Parameter()]
        [string[]]$MobileAppPlatforms = @('All')
    )

    $probes = [System.Collections.Generic.List[hashtable]]::new()

    if ($Imports.ContainsKey('deviceFilters') -and $Imports.deviceFilters) {
        $probes.Add(@{
                Workload      = 'Device Filters'
                Endpoint      = 'beta/deviceManagement/assignmentFilters'
                Uri           = 'beta/deviceManagement/assignmentFilters?$top=1&$select=id'
                RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
                RoleHint      = 'Use a Global Administrator account with active Intune service access; PIM-elevated roles can still be rejected by the downstream Intune service.'
            })
    }

    if ($Imports.ContainsKey('mobileApps') -and $Imports.mobileApps) {
        $probes.Add(@{
                Workload      = 'Mobile Apps'
                Endpoint      = 'beta/deviceAppManagement/mobileApps'
                Uri           = 'beta/deviceAppManagement/mobileApps?$top=1&$select=id'
                RequiredScope = 'DeviceManagementApps.ReadWrite.All'
                RoleHint      = 'Use a Global Administrator account with active Intune app management access; PIM-elevated roles can still be rejected by the downstream Intune service.'
            })

        $remediationEnabled = $true
        if ($MobileAppConfiguration.ContainsKey('remediationEnabled') -and $null -ne $MobileAppConfiguration.remediationEnabled) {
            $remediationEnabled = [bool]$MobileAppConfiguration.remediationEnabled
        }

        if ($remediationEnabled -and (Test-HydrationMobileAppsIncludeWinGet -Configuration $MobileAppConfiguration -Platforms $MobileAppPlatforms)) {
            $probes.Add(@{
                    Workload      = 'WinGet Proactive Remediations'
                    Endpoint      = 'beta/deviceManagement/deviceHealthScripts'
                    Uri           = 'beta/deviceManagement/deviceHealthScripts?$top=1&$select=id'
                    RequiredScope = 'DeviceManagementScripts.ReadWrite.All'
                    RoleHint      = 'Use a Global Administrator account with active Intune device script access; PIM-elevated roles can still be rejected by the downstream Intune service.'
                })
        }
    }

    return $probes.ToArray()
}
