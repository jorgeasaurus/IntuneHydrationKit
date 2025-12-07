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
                }
                elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(
                            @{
                                skuPartNumber = 'ENTERPRISEPACK'
                                servicePlans  = @(
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
                }
                elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                servicePlans = @(@{
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
                }
                elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                servicePlans = @(@{
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
                }
                elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                servicePlans = @(@{
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
                }
                elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                servicePlans = @(@{
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
                }
                elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                servicePlans = @(@{
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
                }
                elseif ($Uri -like '*subscribedSkus*') {
                    return @{
                        value = @(@{
                                servicePlans = @(@{
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
