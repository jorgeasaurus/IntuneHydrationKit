function Get-BaselineImportMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OpenIntune', 'CIS')]
        [string]$Kind
    )

    switch ($Kind) {
        'OpenIntune' {
            return @{
                EndpointMap             = @{
                    'NativeImport'                     = 'deviceManagement/configurationPolicies'
                    'AppProtection'                    = 'deviceAppManagement/managedAppPolicies'
                    'Administrative Templates'         = 'deviceManagement/groupPolicyConfigurations'
                    'Compliance'                       = 'deviceManagement/deviceCompliancePolicies'
                    'Compliance Policies'              = 'deviceManagement/deviceCompliancePolicies'
                    'Configuration Profiles'           = 'deviceManagement/deviceConfigurations'
                    'Device Configuration'             = 'deviceManagement/deviceConfigurations'
                    'Device Enrollment Configurations' = 'deviceManagement/deviceEnrollmentConfigurations'
                    'Endpoint Security'                = 'deviceManagement/intents'
                    'Settings Catalog'                 = 'deviceManagement/configurationPolicies'
                    'Scripts'                          = 'deviceManagement/deviceManagementScripts'
                    'Proactive Remediations'           = 'deviceManagement/deviceHealthScripts'
                    'Windows Autopilot'                = 'deviceManagement/windowsAutopilotDeploymentProfiles'
                    'App Configuration'                = 'deviceAppManagement/mobileAppConfigurations'
                    'App Protection Policies'          = 'deviceAppManagement/managedAppPolicies'
                }
                ODataTypeToEndpoint     = @{
                    '#microsoft.graph.windowsHealthMonitoringConfiguration'         = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windows10GeneralConfiguration'                = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windows10EndpointProtectionConfiguration'     = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windows10CustomConfiguration'                 = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windowsDeliveryOptimizationConfiguration'     = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windowsUpdateForBusinessConfiguration'        = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windowsIdentityProtectionConfiguration'       = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windowsKioskConfiguration'                    = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.editionUpgradeConfiguration'                  = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.sharedPCConfiguration'                        = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windowsWifiConfiguration'                     = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windowsWiredNetworkConfiguration'             = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.macOSGeneralDeviceConfiguration'              = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.macOSCustomConfiguration'                     = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.macOSEndpointProtectionConfiguration'         = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.iosGeneralDeviceConfiguration'                = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.iosCustomConfiguration'                       = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.androidGeneralDeviceConfiguration'            = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.androidWorkProfileGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windows10CompliancePolicy'                    = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.windows81CompliancePolicy'                    = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.macOSCompliancePolicy'                        = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.iosCompliancePolicy'                          = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.androidCompliancePolicy'                      = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.androidWorkProfileCompliancePolicy'           = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.androidDeviceOwnerCompliancePolicy'           = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.deviceManagementConfigurationPolicy'          = 'deviceManagement/configurationPolicies'
                    '#microsoft.graph.windowsDriverUpdateProfile'                   = 'deviceManagement/windowsDriverUpdateProfiles'
                    '#microsoft.graph.androidManagedAppProtection'                  = 'deviceAppManagement/androidManagedAppProtections'
                    '#microsoft.graph.iosManagedAppProtection'                      = 'deviceAppManagement/iosManagedAppProtections'
                }
                IntuneManagementFolders = @('IntuneManagement', 'AppProtection')
                SkipFolders             = @('NativeImport')
            }
        }
        'CIS' {
            return @{
                ODataTypeToEndpoint    = @{
                    '#microsoft.graph.deviceManagementConfigurationPolicy'      = 'deviceManagement/configurationPolicies'
                    '#microsoft.graph.groupPolicyConfiguration'                 = 'deviceManagement/groupPolicyConfigurations'
                    '#microsoft.graph.deviceManagementIntent'                   = 'deviceManagement/intents'
                    '#microsoft.graph.deviceManagementCompliancePolicy'         = 'deviceManagement/compliancePolicies'
                    '#microsoft.graph.windows10CompliancePolicy'                = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.macOSCompliancePolicy'                    = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.iosCompliancePolicy'                      = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.androidCompliancePolicy'                  = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.androidWorkProfileCompliancePolicy'       = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.androidDeviceOwnerCompliancePolicy'       = 'deviceManagement/deviceCompliancePolicies'
                    '#microsoft.graph.windowsHealthMonitoringConfiguration'     = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windows10CustomConfiguration'             = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.sharedPCConfiguration'                    = 'deviceManagement/deviceConfigurations'
                    '#microsoft.graph.windowsDeliveryOptimizationConfiguration' = 'deviceManagement/deviceConfigurations'
                }
                ODataContextToEndpoint = @{
                    'deviceManagement/configurationPolicies'     = 'deviceManagement/configurationPolicies'
                    'deviceManagement/groupPolicyConfigurations' = 'deviceManagement/groupPolicyConfigurations'
                    'deviceManagement/intents'                   = 'deviceManagement/intents'
                    'deviceManagement/compliancePolicies'        = 'deviceManagement/compliancePolicies'
                    'deviceManagement/deviceCompliancePolicies'  = 'deviceManagement/deviceCompliancePolicies'
                    'deviceManagement/deviceConfigurations'      = 'deviceManagement/deviceConfigurations'
                }
                PlatformValueMapping   = @{
                    'windows10'         = 'Windows'
                    'windows10AndLater' = 'Windows'
                    'androidEnterprise' = 'Android'
                    'android'           = 'Android'
                    'iOS'               = 'iOS'
                    'macOS'             = 'macOS'
                    'linux'             = 'Linux'
                }
            }
        }
    }
}
