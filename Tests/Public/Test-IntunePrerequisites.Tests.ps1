#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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
                param($Method, $Uri)

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

            # Should not throw but should warn about missing P2
            { Test-IntunePrerequisites -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should warn when Premium P2 is not detected' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)

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

            # Capture warnings
            $warnings = @()
            Test-IntunePrerequisites -WarningVariable warnings -WarningAction SilentlyContinue

            # Check that the warning was generated (first warning message)
            $warnings[0] | Should -BeLike '*No Azure AD Premium P2 license found*'
            # Verify the second warning about affected policies was also generated
            $warnings[1] | Should -BeLike '*Affected policies*'
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
