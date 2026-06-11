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
        [string[]]$MobileAppPlatforms = @('All'),

        [Parameter()]
        [string[]]$AppProtectionPlatforms = @('All'),

        [Parameter()]
        [string[]]$BaselinePlatforms = @('All')
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

        $remediationEnabled = Get-HydrationMobileAppRemediationEnabled -Configuration $MobileAppConfiguration

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

    $appProtectionProbePlatforms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Imports.ContainsKey('appProtection') -and $Imports.appProtection) {
        foreach ($endpointInfo in (Get-AppProtectionEndpointInfo -Platform $AppProtectionPlatforms)) {
            [void]$appProtectionProbePlatforms.Add($endpointInfo.Platform)
        }
    }

    if ($Imports.ContainsKey('openIntuneBaseline') -and $Imports.openIntuneBaseline) {
        foreach ($endpointInfo in (Get-AppProtectionEndpointInfo -Platform $BaselinePlatforms)) {
            [void]$appProtectionProbePlatforms.Add($endpointInfo.Platform)
        }
    }

    foreach ($endpointInfo in (Get-AppProtectionEndpointInfo)) {
        if ($appProtectionProbePlatforms.Contains($endpointInfo.Platform)) {
            $probes.Add(@{
                    Workload      = 'App Protection'
                    Endpoint      = $endpointInfo.Endpoint
                    Uri           = "$($endpointInfo.Endpoint)`?`$top=1"
                    RequiredScope = 'DeviceManagementApps.ReadWrite.All'
                    RoleHint      = 'Use a Global Administrator account with active Intune app protection access; PIM-elevated roles can still be rejected by the downstream Intune service.'
                })
        }
    }

    if ($Imports.ContainsKey('conditionalAccess') -and $Imports.conditionalAccess) {
        $probes.Add(@{
                Workload      = 'Conditional Access'
                Endpoint      = 'beta/identity/conditionalAccess/policies'
                Uri           = 'beta/identity/conditionalAccess/policies?$top=1&$select=id,displayName,state'
                RequiredScope = 'Policy.ReadWrite.ConditionalAccess'
                RoleHint      = 'Use a Global Administrator, Security Administrator, or Conditional Access Administrator account with active Conditional Access access.'
            })
    }

    return $probes.ToArray()
}
