#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
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

            { Test-IntunePrerequisites } | Should -Throw '*Pre-flight checks failed*'
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

            { Test-IntunePrerequisites } | Should -Throw '*Pre-flight checks failed*'
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

            { Test-IntunePrerequisites } | Should -Throw '*Pre-flight checks failed*'
        }

        It 'Should throw when missing required scopes' {
            Mock Get-MgContext {
                return @{
                    Scopes = @('User.Read')  # Missing required scopes
                }
            } -ModuleName IntuneHydrationKit

            { Test-IntunePrerequisites } | Should -Throw '*Pre-flight checks failed*'
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

    Context 'Target Access Validation' {
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

        It 'Should validate selected workload access before returning success' {
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
            Mock Invoke-HydrationGraphRequest {
                return @{ value = @() }
            } -ModuleName IntuneHydrationKit

            $checks = @(
                [PSCustomObject]@{
                    Name          = 'Mobile Apps'
                    Workload      = 'MobileApps'
                    Uri           = 'beta/deviceAppManagement/mobileApps?$select=id,displayName&$top=1'
                }
            )

            { Test-IntunePrerequisites -RequiredAccessChecks $checks } | Should -Not -Throw

            Should -Invoke Invoke-HydrationGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -like '*deviceAppManagement/mobileApps*'
            } -Times 1
        }

        It 'Should throw a concise prerequisite error when selected workload access is denied' {
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
            Mock Invoke-HydrationGraphRequest {
                param($Uri)

                if ($Uri -like '*deviceAppManagement/mobileApps*') {
                    throw [System.Net.Http.HttpRequestException]::new(
                        'Response status code does not indicate success: Unauthorized (Unauthorized). {"Message":"An error has occurred - Activity ID: 8d674684-71cb-41b4-aba8-869da4d41ac2 - Url: https://proxy.msua08.manage.microsoft.com/..."}',
                        $null,
                        [System.Net.HttpStatusCode]::Unauthorized
                    )
                }
            } -ModuleName IntuneHydrationKit

            $checks = @(
                [PSCustomObject]@{
                    Name          = 'Mobile Apps'
                    Workload      = 'MobileApps'
                    Uri           = 'beta/deviceAppManagement/mobileApps?$select=id,displayName&$top=1'
                }
            )

            $exceptionMessage = $null
            $targetObject = 'not cleared'
            $messages = @()
            try {
                Test-IntunePrerequisites -RequiredAccessChecks $checks -InformationVariable messages -InformationAction Continue
            } catch {
                $exceptionMessage = $_.Exception.Message
                $targetObject = $_.TargetObject
            }

            $messageText = ($messages | ForEach-Object { $_.MessageData }) -join "`n"
            $exceptionMessage | Should -Be 'Pre-flight checks failed. Resolve the prerequisite warning(s) above and retry.'
            $targetObject | Should -BeNullOrEmpty
            $messageText | Should -Match 'Access denied for selected imports: Mobile Apps\.'
            $messageText | Should -Match 'Global Administrator account required for selected imports\.'
            $messageText | Should -Not -Match 'Graph scope present'
            $messageText | Should -Not -Match 'Access guidance'
            $messageText | Should -Not -Match 'Mobile Apps access denied'
            $messageText | Should -Not -Match 'Activity ID'
            $messageText | Should -Not -Match 'proxy\.msua'
            $exceptionMessage | Should -Not -Match 'Activity ID'
            $exceptionMessage | Should -Not -Match 'proxy\.msua'
        }

        It 'Should summarize repeated access-denied checks in one role warning' {
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
            Mock Invoke-HydrationGraphRequest {
                param($Uri)

                if ($Uri -like '*deviceAppManagement*') {
                    throw [System.Net.Http.HttpRequestException]::new(
                        'Response status code does not indicate success: Unauthorized (Unauthorized).',
                        $null,
                        [System.Net.HttpStatusCode]::Unauthorized
                    )
                } elseif ($Uri -like '*conditionalAccess*') {
                    throw [System.Net.Http.HttpRequestException]::new(
                        'Response status code does not indicate success: Forbidden (Forbidden).',
                        $null,
                        [System.Net.HttpStatusCode]::Forbidden
                    )
                } elseif ($Uri -like '*groups*') {
                    throw [System.Net.Http.HttpRequestException]::new(
                        'Response status code does not indicate success: Forbidden (Forbidden).',
                        $null,
                        [System.Net.HttpStatusCode]::Forbidden
                    )
                }
            } -ModuleName IntuneHydrationKit

            $checks = @(
                [PSCustomObject]@{
                    Name          = 'Mobile Apps'
                    Workload      = 'MobileApps'
                    Uri           = 'beta/deviceAppManagement/mobileApps?$select=id,displayName&$top=1'
                }
                [PSCustomObject]@{
                    Name          = 'App Protection'
                    Workload      = 'AppProtection'
                    Uri           = 'beta/deviceAppManagement/managedAppPolicies?$select=id,displayName&$top=1'
                }
                [PSCustomObject]@{
                    Name          = 'Conditional Access'
                    Workload      = 'ConditionalAccess'
                    Uri           = 'beta/identity/conditionalAccess/policies?$select=id,displayName&$top=1'
                }
                [PSCustomObject]@{
                    Name          = 'Groups'
                    Workload      = 'Groups'
                    Uri           = 'v1.0/groups?$select=id,displayName&$top=1'
                }
            )

            $messages = @()
            try {
                Test-IntunePrerequisites -RequiredAccessChecks $checks -InformationVariable messages -InformationAction Continue
            } catch {
                $_.Exception.Message | Should -Be 'Pre-flight checks failed. Resolve the prerequisite warning(s) above and retry.'
            }

            $messageText = ($messages | ForEach-Object { $_.MessageData }) -join "`n"
            $messageText | Should -Match 'Access denied for selected imports: App Protection, Conditional Access, Groups, Mobile Apps\.'
            $messageText | Should -Match 'Global Administrator account required for selected imports\.'
            $messageText | Should -Not -Match 'Graph scope present'
            $messageText | Should -Not -Match 'Conditional Access Administrator'
            $messageText | Should -Not -Match 'Groups Administrator'
            $messageText | Should -Not -Match 'Mobile Apps access denied'
            $messageText | Should -Not -Match 'App Protection access denied'
        }

        It 'Should not classify transient Graph probe failures as missing permissions' {
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
            Mock Invoke-HydrationGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    'Response status code does not indicate success: ServiceUnavailable (ServiceUnavailable).',
                    $null,
                    [System.Net.HttpStatusCode]::ServiceUnavailable
                )
            } -ModuleName IntuneHydrationKit

            $checks = @(
                [PSCustomObject]@{
                    Name          = 'Mobile Apps'
                    Workload      = 'MobileApps'
                    Uri           = 'beta/deviceAppManagement/mobileApps?$select=id,displayName&$top=1'
                }
            )

            $messages = @()
            { Test-IntunePrerequisites -RequiredAccessChecks $checks -InformationVariable messages -InformationAction Continue } |
                Should -Throw '*Failed to validate prerequisites: Failed to validate Graph access for Mobile Apps*'

            $messageText = ($messages | ForEach-Object { $_.MessageData }) -join "`n"
            $messageText | Should -Not -Match 'Access denied for selected imports'
            $messageText | Should -Not -Match 'Access guidance:'
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

        It 'Should not emit Conditional Access notes when Conditional Access is not selected' {
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
            $messageData | Should -Not -Contain '📝 Notes:'
            $messageData | Should -Not -Contain '  • Azure AD Premium P2 not detected. Risk-based Conditional Access templates will be skipped:'
            $messageData | Should -Not -Contain '  • Some Conditional Access templates use private preview features and will be skipped unless the tenant is explicitly authorized.'
        }

        It 'Should emit Conditional Access notes when Conditional Access is selected and Premium P2 is not detected' {
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
            Mock Invoke-HydrationGraphRequest {
                return @{ value = @() }
            } -ModuleName IntuneHydrationKit

            $conditionalAccessCheck = [PSCustomObject]@{
                Name          = 'Conditional Access'
                Workload      = 'ConditionalAccess'
                Uri           = 'beta/identity/conditionalAccess/policies?$select=id,displayName&$top=1'
            }

            $messages = @()
            Test-IntunePrerequisites -RequiredAccessChecks @($conditionalAccessCheck) -InformationVariable messages -InformationAction Continue | Out-Null

            $messageData = $messages | ForEach-Object { $_.MessageData }
            $messageData | Should -Contain '📝 Notes:'
            $messageData | Should -Contain '  • Azure AD Premium P2 not detected. Risk-based Conditional Access templates will be skipped:'
            $messageData | Should -Contain "    ↳ 'Require multifactor authentication for risky sign-ins'"
            $messageData | Should -Contain "    ↳ 'Require password change for high-risk users'"
            $messageData | Should -Contain "    ↳ 'Block high risk agent identities'"
            $messageData | Should -Contain "    ↳ 'Block access to Office365 apps for users with insider risk'"
            $messageData | Should -Contain '  • Some Conditional Access templates use private preview features and will be skipped unless the tenant is explicitly authorized.'
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
