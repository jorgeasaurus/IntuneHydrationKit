function Get-HydrationGraphScopes {
    [CmdletBinding()]
    param()

    return @(
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
}
