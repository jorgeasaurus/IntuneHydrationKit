function Get-HydrationGraphScopes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Hydration', 'ConditionalAccess')]
        [string]$Profile = 'Hydration'
    )

    $scopeProfiles = @{
        Hydration         = @(
            'DeviceManagementConfiguration.ReadWrite.All',
            'DeviceManagementServiceConfig.ReadWrite.All',
            'DeviceManagementManagedDevices.ReadWrite.All',
            'DeviceManagementScripts.ReadWrite.All',
            'DeviceManagementApps.ReadWrite.All',
            'Group.ReadWrite.All',
            'Policy.Read.All',
            'Policy.ReadWrite.ConditionalAccess',
            'Application.Read.All',
            'Directory.ReadWrite.All',
            'LicenseAssignment.Read.All',
            'Organization.Read.All'
        )
        ConditionalAccess = @(
            'Policy.Read.All',
            'Policy.ReadWrite.ConditionalAccess',
            'Application.Read.All',
            'LicenseAssignment.Read.All',
            'Organization.Read.All'
        )
    }

    return $scopeProfiles[$Profile]
}
