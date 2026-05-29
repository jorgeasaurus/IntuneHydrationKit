function Get-HydrationGraphScopes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Imports,

        [Parameter()]
        [switch]$Create,

        [Parameter()]
        [switch]$Delete,

        [Parameter()]
        [hashtable]$MobileAppConfiguration = @{},

        [Parameter()]
        [string[]]$MobileAppPlatforms = @('All')
    )

    $allScopes = @(
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

    if (-not $Imports -or $Imports.Count -eq 0) {
        return $allScopes
    }

    $scopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($scope in @('Organization.Read.All', 'LicenseAssignment.Read.All')) {
        [void]$scopes.Add($scope)
    }

    $scopeMap = @{
        dynamicGroups         = @('Group.ReadWrite.All')
        staticGroups          = @('Group.ReadWrite.All')
        deviceFilters         = @('DeviceManagementConfiguration.ReadWrite.All')
        conditionalAccess     = @('Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'Application.Read.All', 'Directory.ReadWrite.All')
        complianceTemplates   = @('DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementScripts.ReadWrite.All')
        openIntuneBaseline    = @('DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementServiceConfig.ReadWrite.All', 'DeviceManagementApps.ReadWrite.All', 'DeviceManagementScripts.ReadWrite.All')
        enrollmentProfiles    = @('DeviceManagementServiceConfig.ReadWrite.All', 'DeviceManagementConfiguration.ReadWrite.All', 'Group.ReadWrite.All')
        appProtection         = @('DeviceManagementApps.ReadWrite.All')
        notificationTemplates = @('DeviceManagementServiceConfig.ReadWrite.All')
        mobileApps            = @('DeviceManagementApps.ReadWrite.All')
        cisBaselines          = @('DeviceManagementConfiguration.ReadWrite.All')
    }

    foreach ($importKey in $Imports.Keys) {
        if (-not $Imports[$importKey] -or -not $scopeMap.ContainsKey($importKey)) {
            continue
        }

        foreach ($scope in $scopeMap[$importKey]) {
            [void]$scopes.Add($scope)
        }
    }

    $includeCreateOnlyScopes = $Create.IsPresent -or -not $Delete.IsPresent
    if ($includeCreateOnlyScopes -and $Imports.ContainsKey('staticGroups') -and $Imports.staticGroups) {
        foreach ($scope in @('Application.Read.All', 'Directory.ReadWrite.All')) {
            [void]$scopes.Add($scope)
        }
    }

    $remediationEnabled = $true
    if ($MobileAppConfiguration -and $MobileAppConfiguration.ContainsKey('remediationEnabled') -and $null -ne $MobileAppConfiguration.remediationEnabled) {
        $remediationEnabled = [bool]$MobileAppConfiguration.remediationEnabled
    }
    if ($Imports.ContainsKey('mobileApps') -and $Imports.mobileApps -and $remediationEnabled -and
        (Test-HydrationMobileAppsIncludeWinGet -Configuration $MobileAppConfiguration -Platforms $MobileAppPlatforms)) {
        [void]$scopes.Add('DeviceManagementScripts.ReadWrite.All')
    }

    return @($allScopes | Where-Object { $scopes.Contains($_) })
}
