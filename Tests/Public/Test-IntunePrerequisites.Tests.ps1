#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    function Set-RequiredGraphContextMock {
        Mock Get-MgContext {
            return @{
                Scopes = @(
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
        } -ModuleName IntuneHydrationKit
    }

    function Set-PrerequisiteGraphRequestMock {
        param(
            [scriptblock]$AssignmentFilterResponse,

            [scriptblock]$MobileAppsResponse,

            [scriptblock]$DeviceHealthScriptsResponse,

            [scriptblock]$IosAppProtectionResponse,

            [scriptblock]$AndroidAppProtectionResponse,

            [scriptblock]$ConditionalAccessResponse
        )

        $script:AssignmentFilterResponse = $AssignmentFilterResponse
        $script:MobileAppsResponse = $MobileAppsResponse
        $script:DeviceHealthScriptsResponse = $DeviceHealthScriptsResponse
        $script:IosAppProtectionResponse = $IosAppProtectionResponse
        $script:AndroidAppProtectionResponse = $AndroidAppProtectionResponse
        $script:ConditionalAccessResponse = $ConditionalAccessResponse
        Mock Invoke-MgGraphRequest {
            param($Uri)

            if ($Uri -like '*organization*') {
                return @{ value = @(@{ displayName = 'Test Organization' }) }
            }
            if ($Uri -like '*subscribedSkus*') {
                return @{
                    value = @(@{
                            capabilityStatus = 'Enabled'
                            servicePlans     = @(@{
                                    servicePlanName    = 'INTUNE_A'
                                    provisioningStatus = 'Success'
                                })
                        })
                }
            }
            if ($Uri -like '*assignmentFilters*' -and $script:AssignmentFilterResponse) {
                return & $script:AssignmentFilterResponse
            }
            if ($Uri -like '*deviceAppManagement/mobileApps*' -and $script:MobileAppsResponse) {
                return & $script:MobileAppsResponse
            }
            if ($Uri -like '*deviceManagement/deviceHealthScripts*' -and $script:DeviceHealthScriptsResponse) {
                return & $script:DeviceHealthScriptsResponse
            }
            if ($Uri -like '*deviceAppManagement/iosManagedAppProtections*' -and $script:IosAppProtectionResponse) {
                return & $script:IosAppProtectionResponse
            }
            if ($Uri -like '*deviceAppManagement/androidManagedAppProtections*' -and $script:AndroidAppProtectionResponse) {
                return & $script:AndroidAppProtectionResponse
            }
            if ($Uri -like '*identity/conditionalAccess/policies*' -and $script:ConditionalAccessResponse) {
                return & $script:ConditionalAccessResponse
            }
        } -ModuleName IntuneHydrationKit
    }
}

Describe 'Test-IntunePrerequisites' {
    Context 'Parameter Validation' {
        It 'Should have CmdletBinding attribute' {
            $command = Get-Command Test-IntunePrerequisites
            $command.CmdletBinding | Should -Be $true
        }

        It 'Should not require any mandatory parameters' {
            $command = Get-Command Test-IntunePrerequisites
            $mandatoryParams = $command.Parameters.Values |
                Where-Object {
                    $_.Attributes | Where-Object {
                        $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                    }
                }

            $mandatoryParams | Should -BeNullOrEmpty
        }
    }

    Context 'Successful Prerequisites Check' {
        BeforeAll {
            # Mock Graph API calls
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{
                        value = @(
                            @{
                                displayName = 'Test Organization'
                                id          = '12345678-1234-1234-1234-123456789abc'
                            }
                        )
                    }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(
                            @{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = 'ENTERPRISEPACK'
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    }
                                )
                            }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            # Mock Get-MgContext with all required scopes
            Mock Get-MgContext {
                return @{
                    Scopes = @(
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
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return true when all prerequisites pass' {
            $result = Test-IntunePrerequisites

            $result | Should -Be $true
        }

        It 'Should query organization endpoint' {
            Test-IntunePrerequisites

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -like '*organization*'
            }
        }

        It 'Should query subscribedSkus endpoint' {
            Test-IntunePrerequisites

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -like '*subscribedSkus*'
            }
        }
    }

    Context 'Workload Access Validation' {
        BeforeEach {
            Set-RequiredGraphContextMock
        }

        It 'Should probe device filter access when DeviceFilters is selected' {
            Set-PrerequisiteGraphRequestMock -AssignmentFilterResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ deviceFilters = $true } | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceManagement/assignmentFilters*'
            }
        }

        It 'Should fail pre-flight with a concise device filter access issue on Intune backend 401 Forbidden' {
            Set-PrerequisiteGraphRequestMock -AssignmentFilterResponse {
                throw 'HTTP/2.0 401 Unauthorized {"error":{"code":"UnknownError","message":"{\"ErrorCode\":\"Forbidden\"}"}}'
            }

            { Test-IntunePrerequisites -Imports @{ deviceFilters = $true } } |
                Should -Throw '*Device Filters access check failed*HTTP 401*DeviceManagementConfiguration.ReadWrite.All*Global Administrator*'
        }

        It 'Should not probe device filter access when DeviceFilters is not selected' {
            Set-PrerequisiteGraphRequestMock

            Test-IntunePrerequisites -Imports @{ deviceFilters = $false } | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceManagement/assignmentFilters*'
            }
        }

        It 'Should not emit Conditional Access notes when only DeviceFilters is selected' {
            Set-PrerequisiteGraphRequestMock -AssignmentFilterResponse { @{ value = @() } }

            $messages = @()
            Test-IntunePrerequisites -Imports @{ deviceFilters = $true; conditionalAccess = $false } -InformationVariable messages -InformationAction Continue | Out-Null

            $messageData = $messages | ForEach-Object { $_.MessageData }
            $messageData | Should -Not -Contain '  • Azure AD Premium P2 not detected. Risk-based Conditional Access templates will be skipped:'
            $messageData | Should -Not -Contain '  • Some Conditional Access templates use private preview features and will be skipped unless the tenant is explicitly authorized.'
        }

        It 'Should probe mobile app and WinGet remediation access when MobileApps is selected' {
            Set-PrerequisiteGraphRequestMock `
                -MobileAppsResponse { @{ value = @() } } `
                -DeviceHealthScriptsResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ mobileApps = $true } | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/mobileApps*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceManagement/deviceHealthScripts*'
            }
        }

        It 'Should skip WinGet remediation access probe when remediation is disabled' {
            Set-PrerequisiteGraphRequestMock -MobileAppsResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ mobileApps = $true } -MobileAppConfiguration @{ remediationEnabled = $false } | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/mobileApps*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceManagement/deviceHealthScripts*'
            }
        }

        It 'Should skip WinGet remediation access probe when Windows mobile apps are not selected' {
            Set-PrerequisiteGraphRequestMock -MobileAppsResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ mobileApps = $true } -MobileAppPlatforms @('macOS') | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/mobileApps*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceManagement/deviceHealthScripts*'
            }
        }

        It 'Should skip WinGet remediation access probe when selected template IDs are legacy mobile apps only' {
            Set-PrerequisiteGraphRequestMock -MobileAppsResponse { @{ value = @() } }

            Test-IntunePrerequisites `
                -Imports @{ mobileApps = $true } `
                -MobileAppConfiguration @{ remediationEnabled = $true; templateIds = @('CompanyPortal', 'M365Apps') } `
                -MobileAppPlatforms @('Windows') |
                Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/mobileApps*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceManagement/deviceHealthScripts*'
            }
        }

        It 'Should fail pre-flight with a concise mobile app access issue on Intune backend 403' {
            Set-PrerequisiteGraphRequestMock -MobileAppsResponse {
                throw 'HTTP/2.0 403 Forbidden {"error":{"code":"UnknownError","message":"User is not authorized to perform this operation"}}'
            }

            { Test-IntunePrerequisites -Imports @{ mobileApps = $true } } |
                Should -Throw '*Mobile Apps access check failed*HTTP 403*DeviceManagementApps.ReadWrite.All*Global Administrator*'
        }

        It 'Should probe both app protection endpoints when AppProtection is selected for all platforms' {
            Set-PrerequisiteGraphRequestMock `
                -IosAppProtectionResponse { @{ value = @() } } `
                -AndroidAppProtectionResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ appProtection = $true } | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/iosManagedAppProtections*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/androidManagedAppProtections*'
            }
        }

        It 'Should probe only selected app protection platform endpoints' {
            Set-PrerequisiteGraphRequestMock -IosAppProtectionResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ appProtection = $true } -AppProtectionPlatforms @('iOS') | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/iosManagedAppProtections*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceAppManagement/androidManagedAppProtections*'
            }
        }

        It 'Should fail pre-flight with a concise app protection access issue on Intune backend 401' {
            Set-PrerequisiteGraphRequestMock -IosAppProtectionResponse {
                throw 'HTTP/2.0 401 Unauthorized {"error":{"code":"UnknownError","message":"{\"ErrorCode\":\"Forbidden\",\"Message\":\"https://proxy.msua08.manage.microsoft.com/MAMAdmin\"}"}}'
            }

            try {
                Test-IntunePrerequisites -Imports @{ appProtection = $true } -AppProtectionPlatforms @('iOS')
                throw 'Expected prerequisite failure'
            } catch {
                $_.Exception.Message | Should -Match 'App Protection access check failed'
                $_.Exception.Message | Should -Match 'HTTP 401'
                $_.Exception.Message | Should -Match 'DeviceManagementApps.ReadWrite.All'
                $_.Exception.Message | Should -Match 'Global Administrator'
                $_.Exception.Message | Should -Not -Match 'proxy\.msua08'
            }
        }

        It 'Should probe selected BYOD app protection endpoints when OpenIntuneBaseline can import them' {
            Set-PrerequisiteGraphRequestMock `
                -IosAppProtectionResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ openIntuneBaseline = $true } -BaselinePlatforms @('iOS') | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceAppManagement/iosManagedAppProtections*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceAppManagement/androidManagedAppProtections*'
            }
        }

        It 'Should skip BYOD app protection probes when OpenIntuneBaseline is Windows-only' {
            Set-PrerequisiteGraphRequestMock

            Test-IntunePrerequisites -Imports @{ openIntuneBaseline = $true } -BaselinePlatforms @('Windows') | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceAppManagement/iosManagedAppProtections*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*deviceAppManagement/androidManagedAppProtections*'
            }
        }

        It 'Should probe Conditional Access access when ConditionalAccess is selected' {
            Set-PrerequisiteGraphRequestMock -ConditionalAccessResponse { @{ value = @() } }

            Test-IntunePrerequisites -Imports @{ conditionalAccess = $true } | Should -Be $true

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*identity/conditionalAccess/policies*'
            }
        }

        It 'Should fail pre-flight with a concise Conditional Access access issue on Graph 403' {
            Set-PrerequisiteGraphRequestMock -ConditionalAccessResponse {
                throw 'HTTP/2.0 403 Forbidden {"error":{"code":"AccessDenied","message":"Your account does not have access to this report or data."}}'
            }

            { Test-IntunePrerequisites -Imports @{ conditionalAccess = $true } } |
                Should -Throw '*Conditional Access access check failed*HTTP 403*Policy.ReadWrite.ConditionalAccess*Conditional Access Administrator*'
        }
    }

    Context 'License Validation' {
        BeforeAll {
            Mock Get-MgContext {
                return @{
                    Scopes = @(
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
            } -ModuleName IntuneHydrationKit
        }

        It 'Should detect INTUNE_A license' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                servicePlans     = @(@{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    })
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }

        It 'Should detect INTUNE_EDU license' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                servicePlans     = @(@{
                                        servicePlanName    = 'INTUNE_EDU'
                                        provisioningStatus = 'Success'
                                    })
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }

        It 'Should detect EMSPREMIUM license' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                servicePlans     = @(@{
                                        servicePlanName    = 'EMSPREMIUM'
                                        provisioningStatus = 'Success'
                                    })
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }

        It 'Should throw when no Intune license is found' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                servicePlans     = @(@{
                                        servicePlanName    = 'SOME_OTHER_LICENSE'
                                        provisioningStatus = 'Success'
                                    })
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Throw '*Intune*'
        }

        It 'Should not count licenses with pending provisioning status' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                servicePlans     = @(@{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Pending'
                                    })
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Throw '*Intune*'
        }
    }

    Context 'Permission Scope Validation' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                servicePlans     = @(@{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    })
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should throw when not connected to Graph' {
            Mock Get-MgContext { return $null } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Throw '*not connected*'
        }

        It 'Should throw when missing required scopes' {
            Mock Get-MgContext {
                return @{
                    Scopes = @('User.Read')  # Missing required scopes
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Throw '*Missing*scope*'
        }

        It 'Should validate only selected workload scopes when imports are provided' {
            Mock Get-MgContext {
                return @{
                    Scopes = @(
                        'Organization.Read.All',
                        'LicenseAssignment.Read.All',
                        'DeviceManagementConfiguration.ReadWrite.All'
                    )
                }
            } -ModuleName IntuneHydrationKit

            {
                Test-IntunePrerequisites -Imports @{
                    deviceFilters     = $true
                    conditionalAccess = $false
                    mobileApps        = $false
                }
            } | Should -Not -Throw
        }

        It 'Should honor explicit required scopes from orchestration' {
            Mock Get-MgContext {
                return @{
                    Scopes = @(
                        'Organization.Read.All',
                        'LicenseAssignment.Read.All',
                        'DeviceManagementConfiguration.ReadWrite.All'
                    )
                }
            } -ModuleName IntuneHydrationKit

            {
                Test-IntunePrerequisites `
                    -Imports @{ deviceFilters = $true } `
                    -RequiredScopes @('Organization.Read.All', 'Group.ReadWrite.All')
            } | Should -Throw '*Group.ReadWrite.All*'
        }

        It 'Should pass when all required scopes are present' {
            Mock Get-MgContext {
                return @{
                    Scopes = @(
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
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }
    }

    Context 'Premium P2 License Detection' {
        BeforeAll {
            Mock Get-MgContext {
                return @{
                    Scopes = @(
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
            } -ModuleName IntuneHydrationKit
        }

        It 'Should detect AAD_PREMIUM_P2 license' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = 'AAD_PREMIUM_P2'
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    },
                                    @{
                                        servicePlanName    = 'AAD_PREMIUM_P2'
                                        provisioningStatus = 'Success'
                                    }
                                )
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }

        It 'Should detect Microsoft 365 E5 license (SPE_E5)' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = 'SPE_E5'
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    },
                                    @{
                                        servicePlanName    = 'SPE_E5'
                                        provisioningStatus = 'Success'
                                    }
                                )
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }

        It 'Should detect Microsoft 365 Education A5 license' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = 'M365EDU_A5_FACULTY'
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    },
                                    @{
                                        servicePlanName    = 'M365EDU_A5_FACULTY'
                                        provisioningStatus = 'Success'
                                    }
                                )
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }

        It 'Should detect Identity & Threat Protection license' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = 'IDENTITY_THREAT_PROTECTION'
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    },
                                    @{
                                        servicePlanName    = 'IDENTITY_THREAT_PROTECTION'
                                        provisioningStatus = 'Success'
                                    }
                                )
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Not -Throw
        }

        It 'Should skip disabled SKUs when checking for P2 licenses' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(
                            @{
                                capabilityStatus = 'Disabled'
                                skuPartNumber    = 'AAD_PREMIUM_P2'
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'AAD_PREMIUM_P2'
                                        provisioningStatus = 'Success'
                                    }
                                )
                            },
                            @{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = 'ENTERPRISEPACK'
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    }
                                )
                            }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            # Should not throw when Premium P2 is absent because the missing license is non-blocking
            { Test-IntunePrerequisites -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should emit a note when Premium P2 is not detected' {
            Mock Invoke-MgGraphRequest {
                param($Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = 'ENTERPRISEPACK'
                                servicePlans     = @(@{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    })
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            $messages = @()
            Test-IntunePrerequisites -InformationVariable messages -InformationAction Continue | Out-Null

            $messageData = $messages | ForEach-Object { $_.MessageData }
            $messageData | Should -Contain '📝 Notes:'
            $messageData | Should -Contain '  • Azure AD Premium P2 not detected. Risk-based Conditional Access templates will be skipped:'
            $messageData | Should -Contain "    ↳ 'Require multifactor authentication for risky sign-ins'"
            $messageData | Should -Contain "    ↳ 'Require password change for high-risk users'"
            $messageData | Should -Contain "    ↳ 'Block high risk agent identities'"
            $messageData | Should -Contain "    ↳ 'Block access to Office365 apps for users with insider risk'"
        }

        It 'Should not treat <ServicePlanName> as a Premium P2 license' -ForEach @(
            @{ ServicePlanName = 'ADALLOM_S_STANDALONE' }
            @{ ServicePlanName = 'ATA' }
        ) {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)

                if ($Uri -like '*organization*') {
                    return @{ value = @(@{ displayName = 'Test' }) }
                } elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                capabilityStatus = 'Enabled'
                                skuPartNumber    = $ServicePlanName
                                servicePlans     = @(
                                    @{
                                        servicePlanName    = 'INTUNE_A'
                                        provisioningStatus = 'Success'
                                    },
                                    @{
                                        servicePlanName    = $ServicePlanName
                                        provisioningStatus = 'Success'
                                    }
                                )
                            })
                    }
                }
            } -ModuleName IntuneHydrationKit

            $warnings = @()
            Test-IntunePrerequisites -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings[0] | Should -BeLike '*No Azure AD Premium P2 license found*'
        }
    }

    Context 'API Error Handling' {
        BeforeAll {
            Mock Get-MgContext {
                return @{ Scopes = @('DeviceManagementConfiguration.ReadWrite.All') }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should throw when organization API call fails' {
            Mock Invoke-MgGraphRequest {
                throw 'API Error'
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Throw
        }
    }
}
