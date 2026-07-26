#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../scripts/Set-WindowsOIBSettingsCatalogAssignments.ps1
}

Describe 'Set-WindowsOIBSettingsCatalogAssignments' {
    Context 'Connect-AssignmentGraph' {
        It 'Should connect using the requested configuration policy scope' {
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph {}

            Connect-AssignmentGraph -RequiredScope 'DeviceManagementConfiguration.ReadWrite.All'

            Should -Invoke Connect-MgGraph -Exactly 1 -ParameterFilter {
                $Scopes -eq 'DeviceManagementConfiguration.ReadWrite.All' -and $NoWelcome
            }
        }

        It 'Should reconnect when the requested scope is missing' {
            Mock Get-MgContext {
                [PSCustomObject]@{ Scopes = @('DeviceManagementApps.ReadWrite.All') }
            }
            Mock Disconnect-MgGraph {}
            Mock Connect-MgGraph {}

            Connect-AssignmentGraph -RequiredScope 'DeviceManagementConfiguration.ReadWrite.All'

            Should -Invoke Disconnect-MgGraph -Exactly 1
            Should -Invoke Connect-MgGraph -Exactly 1 -ParameterFilter {
                $Scopes -eq 'DeviceManagementConfiguration.ReadWrite.All' -and $NoWelcome
            }
        }
    }

    Context 'Get-WindowsOIBSettingsCatalogPolicy' {
        BeforeEach {
            Mock Invoke-MgGraphRequest {
                @{
                    value = @(
                        [PSCustomObject]@{ id = 'managed'; platforms = 'windows10'; name = '[IHD] Win - OIB - SC - Managed - D - Policy' }
                        [PSCustomObject]@{ id = 'unmanaged'; platforms = 'windows10'; name = 'Win - OIB - SC - Unmanaged - U - Policy' }
                        [PSCustomObject]@{ id = 'non-oib'; platforms = 'windows10'; name = '[IHD] Other Windows Policy' }
                    )
                }
            }
        }

        It 'Should select only managed OIB policies by default' {
            $result = Get-WindowsOIBSettingsCatalogPolicy

            $result.id | Should -Be 'managed'
        }

        It 'Should allow an explicitly selected unmanaged OIB policy' {
            $result = Get-WindowsOIBSettingsCatalogPolicy -PolicyId 'unmanaged'

            $result.id | Should -Be 'unmanaged'
        }

        It 'Should allow all unmanaged OIB policies only with explicit opt-in' {
            $result = Get-WindowsOIBSettingsCatalogPolicy -IncludeUnmanaged

            $result.id | Should -Be @('managed', 'unmanaged')
        }

        It 'Should resolve one anchored scope marker for managed and unmanaged OIB names' {
            Get-OIBPolicyScope -PolicyName '[IHD] Win - OIB - SC - Test - U - Policy' | Should -Be 'U'
            Get-OIBPolicyScope -PolicyName 'Win - OIB - SC - Test - D - Policy' | Should -Be 'D'
            Get-OIBPolicyScope -PolicyName '[IHD] Other Windows Policy' | Should -BeNullOrEmpty
        }
    }

    Context 'Set-OIBSettingsCatalogAssignment' {
        It 'Should skip an existing unfiltered intended target' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $ContentType)
                $null = $Method, $Uri, $Body, $ContentType
            }
            Mock Get-ConfigurationPolicyAssignment {
                @([PSCustomObject]@{
                        target = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                            deviceAndAppManagementAssignmentFilterType = 'none'
                        }
                    })
            }

            $result = Set-OIBSettingsCatalogAssignment -PolicyId 'policy-id' -PolicyName '[IHD] Win - OIB - SC - Test - U - Policy' -Confirm:$false

            $result.Status | Should -Be 'Skipped'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0
        }

        It 'Should fail rather than treat a filtered target as an unfiltered target' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $ContentType)
                $null = $Method, $Uri, $Body, $ContentType
            }
            Mock Get-ConfigurationPolicyAssignment {
                @([PSCustomObject]@{
                        target = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                            deviceAndAppManagementAssignmentFilterType = 'include'
                            deviceAndAppManagementAssignmentFilterId = 'filter-id'
                        }
                    })
            }

            {
                Set-OIBSettingsCatalogAssignment -PolicyId 'policy-id' -PolicyName '[IHD] Win - OIB - SC - Test - U - Policy' -Confirm:$false
            } | Should -Throw '*filtered All Users assignment*'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0
        }

        It 'Should fail rather than replay a policy-set-owned assignment as direct' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $ContentType)
                $null = $Method, $Uri, $Body, $ContentType
            }
            Mock Get-ConfigurationPolicyAssignment {
                @([PSCustomObject]@{
                        source = 'policySets'
                        sourceId = 'policy-set-id'
                        target = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                            groupId = 'existing-group'
                        }
                    })
            }

            {
                Set-OIBSettingsCatalogAssignment -PolicyId 'policy-id' -PolicyName '[IHD] Win - OIB - SC - Test - D - Policy' -Confirm:$false
            } | Should -Throw '*owned by a policy set*'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0
        }

        It 'Should not write assignments in WhatIf mode' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $ContentType)
                $null = $Method, $Uri, $Body, $ContentType
            }
            Mock Get-ConfigurationPolicyAssignment { @() }

            $result = Set-OIBSettingsCatalogAssignment -PolicyId 'policy-id' -PolicyName '[IHD] Win - OIB - SC - Test - D - Policy' -WhatIf

            $result.Status | Should -Be 'WhatIf'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0
        }

        It 'Should preserve assignments, add the target, and verify the result' {
            $script:assignmentReadCount = 0
            Mock Get-ConfigurationPolicyAssignment {
                $script:assignmentReadCount++
                if ($script:assignmentReadCount -eq 1) {
                    return @([PSCustomObject]@{
                            target = [PSCustomObject]@{
                                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                                groupId = 'existing-group'
                            }
                        })
                }

                return @(
                    [PSCustomObject]@{
                        target = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                            groupId = 'existing-group'
                        }
                    }
                    [PSCustomObject]@{
                        target = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                            deviceAndAppManagementAssignmentFilterType = 'none'
                        }
                    }
                )
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $ContentType)
                $null = $Method, $Uri, $Body, $ContentType
            }

            $result = Set-OIBSettingsCatalogAssignment -PolicyId 'policy-id' -PolicyName '[IHD] Win - OIB - SC - Test - D - Policy' -Confirm:$false

            $result.Status | Should -Be 'Assigned'
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'beta/deviceManagement/configurationPolicies/policy-id/assign' -and
                $Body -match 'existing-group' -and
                $Body -match 'allDevicesAssignmentTarget' -and
                $Body -match '"source"\s*:\s*"direct"'
            }
        }
    }
}
