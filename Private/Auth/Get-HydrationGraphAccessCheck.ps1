function Get-HydrationGraphAccessCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Imports
    )

    $accessCheckDefinitions = @(
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.mobileApps }
            Workload      = 'MobileApps'
            Name          = 'Mobile Apps'
            Uri           = 'beta/deviceAppManagement/mobileApps?$select=id,displayName&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.appProtection }
            Workload      = 'AppProtection'
            Name          = 'App Protection'
            Uri           = 'beta/deviceAppManagement/managedAppPolicies?$select=id,displayName&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.complianceTemplates }
            Workload      = 'CompliancePolicies'
            Name          = 'Compliance Policies'
            Uri           = 'beta/deviceManagement/deviceCompliancePolicies?$select=id,displayName&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.deviceFilters }
            Workload      = 'DeviceFilters'
            Name          = 'Device Filters'
            Uri           = 'beta/deviceManagement/assignmentFilters?$select=id,displayName&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.enrollmentProfiles }
            Workload      = 'EnrollmentProfiles'
            Name          = 'Enrollment Profiles'
            Uri           = 'beta/deviceManagement/windowsAutopilotDeploymentProfiles?$select=id,displayName&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.openIntuneBaseline -or $ImportSettings.cisBaselines }
            Workload      = 'DeviceConfigurationPolicies'
            Name          = 'Device Configuration Policies'
            Uri           = 'beta/deviceManagement/configurationPolicies?$select=id,name&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.notificationTemplates }
            Workload      = 'NotificationTemplates'
            Name          = 'Notification Templates'
            Uri           = 'beta/deviceManagement/notificationMessageTemplates?$select=id,displayName&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.dynamicGroups -or $ImportSettings.staticGroups }
            Workload      = 'Groups'
            Name          = 'Groups'
            Uri           = 'v1.0/groups?$select=id,displayName&$top=1'
        }
        @{
            Enabled       = { param($ImportSettings) $ImportSettings.conditionalAccess }
            Workload      = 'ConditionalAccess'
            Name          = 'Conditional Access'
            Uri           = 'beta/identity/conditionalAccess/policies?$select=id,displayName&$top=1'
        }
    )

    foreach ($definition in $accessCheckDefinitions) {
        if (& $definition.Enabled $Imports) {
            [PSCustomObject]@{
                Name          = $definition.Name
                Workload      = $definition.Workload
                Uri           = $definition.Uri
            }
        }
    }
}
