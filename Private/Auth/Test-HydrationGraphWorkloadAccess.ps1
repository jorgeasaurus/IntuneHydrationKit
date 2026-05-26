function Test-HydrationGraphWorkloadAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Imports,

        [Parameter()]
        [hashtable]$MobileAppConfiguration = @{},

        [Parameter()]
        [string[]]$MobileAppPlatforms = @('All')
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $probes = Get-HydrationGraphWorkloadAccessProbe `
        -Imports $Imports `
        -MobileAppConfiguration $MobileAppConfiguration `
        -MobileAppPlatforms $MobileAppPlatforms

    foreach ($probe in $probes) {
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
