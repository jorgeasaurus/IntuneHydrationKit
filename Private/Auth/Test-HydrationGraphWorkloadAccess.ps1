function Test-HydrationGraphWorkloadAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Imports,

        [Parameter()]
        [bool]$MobileAppsRemediationEnabled = $true,

        [Parameter()]
        [bool]$MobileAppsIncludeWinGet = $true
    )

    $issues = [System.Collections.Generic.List[string]]::new()

    $probes = @(
        @{
            ImportKey      = 'deviceFilters'
            Workload       = 'Device Filters'
            Endpoint       = 'beta/deviceManagement/assignmentFilters'
            Uri            = 'beta/deviceManagement/assignmentFilters?$top=1&$select=id'
            RequiredScope  = 'DeviceManagementConfiguration.ReadWrite.All'
            RoleHint       = 'Use a Global Administrator account with active Intune service access; PIM-elevated roles can still be rejected by the downstream Intune service.'
        },
        @{
            ImportKey      = 'mobileApps'
            Workload       = 'Mobile Apps'
            Endpoint       = 'beta/deviceAppManagement/mobileApps'
            Uri            = 'beta/deviceAppManagement/mobileApps?$top=1&$select=id'
            RequiredScope  = 'DeviceManagementApps.ReadWrite.All'
            RoleHint       = 'Use a Global Administrator account with active Intune app management access; PIM-elevated roles can still be rejected by the downstream Intune service.'
        },
        @{
            ImportKey      = 'mobileApps'
            Workload       = 'WinGet Proactive Remediations'
            Endpoint       = 'beta/deviceManagement/deviceHealthScripts'
            Uri            = 'beta/deviceManagement/deviceHealthScripts?$top=1&$select=id'
            RequiredScope  = 'DeviceManagementScripts.ReadWrite.All'
            RoleHint       = 'Use a Global Administrator account with active Intune device script access; PIM-elevated roles can still be rejected by the downstream Intune service.'
            RequiresMobileAppsRemediation = $true
        }
    )

    foreach ($probe in $probes) {
        if (-not ($Imports.ContainsKey($probe.ImportKey) -and $Imports[$probe.ImportKey])) {
            continue
        }

        if ($probe.RequiresMobileAppsRemediation -and (-not $MobileAppsRemediationEnabled -or -not $MobileAppsIncludeWinGet)) {
            continue
        }

        try {
            $null = Invoke-MgGraphRequest -Method GET -Uri $probe.Uri -ErrorAction Stop
        } catch {
            $issues.Add((Get-HydrationGraphAccessIssue `
                        -ErrorRecord $_ `
                        -Workload $probe.Workload `
                        -Endpoint $probe.Endpoint `
                        -RequiredScope $probe.RequiredScope `
                        -RoleHint $probe.RoleHint))
        }
    }

    return $issues.ToArray()
}
