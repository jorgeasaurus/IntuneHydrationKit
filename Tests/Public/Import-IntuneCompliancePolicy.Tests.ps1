#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Import-IntuneCompliancePolicy' {
    BeforeAll {
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit
        Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit
    }

    Context 'Parameter Validation' {
        It 'Should have TemplatePath parameter' {
            $command = Get-Command Import-IntuneCompliancePolicy
            $param = $command.Parameters['TemplatePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have Platform parameter with ValidateSet' {
            $command = Get-Command Import-IntuneCompliancePolicy
            $param = $command.Parameters['Platform']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Windows'
            $validateSet.ValidValues | Should -Contain 'macOS'
            $validateSet.ValidValues | Should -Contain 'iOS'
            $validateSet.ValidValues | Should -Contain 'Android'
            $validateSet.ValidValues | Should -Contain 'Linux'
            $validateSet.ValidValues | Should -Contain 'All'
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Import-IntuneCompliancePolicy
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneCompliancePolicy
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Create Mode - Standard Compliance Policy' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Windows-Compliance.json'
                        Name     = 'Windows-Compliance.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
    "displayName": "Windows 10 Compliance Policy",
    "description": "Standard Windows compliance policy",
    "passwordRequired": true,
    "osMinimumVersion": "10.0.19041"
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should prefetch existing policies from both endpoints' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                return @{ id = 'new-policy-id'; displayName = 'Windows 10 Compliance Policy' }
            } -ModuleName IntuneHydrationKit

            Import-IntuneCompliancePolicy -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceCompliancePolicies*'
            }
        }

        It 'Should skip policy if it already exists' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @(@{ id = 'existing-id'; displayName = 'Windows 10 Compliance Policy'; description = 'Existing policy' }) }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Skipped'
        }

        It 'Should create policy if it does not exist' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-policy-id'; displayName = 'Windows 10 Compliance Policy' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Created'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*deviceCompliancePolicies*'
            }
        }

        It 'Should append hydration marker to description' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    # Verify the body contains the hydration marker
                    $bodyObj = $Body | ConvertFrom-Json
                    $bodyObj.description | Should -BeLike '*Imported by Intune Hydration Kit*'
                    return @{ id = 'new-policy-id'; displayName = 'Windows 10 Compliance Policy' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneCompliancePolicy -Platform Windows
        }
    }

    Context 'Create Mode - Linux Compliance Policy' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Linux-Compliance.json'
                        Name     = 'Linux-Compliance.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.linuxCompliancePolicy",
    "displayName": "Linux Compliance Policy",
    "description": "",
    "platforms": "linux",
    "technologies": "linuxMdm",
    "name": "Linux Compliance Policy"
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should use compliancePolicies endpoint for Linux' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-policy-id'; name = 'Linux Compliance Policy' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneCompliancePolicy -Platform Linux

            # Linux uses /compliancePolicies (not /deviceCompliancePolicies)
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'beta/deviceManagement/compliancePolicies'
            }
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Compliance.json'; Name = 'Windows-Compliance.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.windows10CompliancePolicy", "displayName": "Test Policy", "description": ""}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should not call POST when WhatIf is specified' {
            Import-IntuneCompliancePolicy -Platform Windows -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST'
            } -Times 0
        }

        It 'Should return WouldCreate action when WhatIf is specified' {
            $result = Import-IntuneCompliancePolicy -Platform Windows -WhatIf

            $result[0].Action | Should -Be 'WouldCreate'
        }
    }

    Context 'Delete Mode' {
        BeforeAll {
            Mock Test-Path { return $true } -ModuleName IntuneHydrationKit
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Compliance.json'; Name = 'Windows-Compliance.json' })
            } -ModuleName IntuneHydrationKit
            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.windows10CompliancePolicy", "displayName": "Test Policy"}'
            } -ModuleName IntuneHydrationKit
        }

        It 'Should list existing policies when RemoveExisting is specified' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'policy-1'; displayName = 'Policy 1'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneCompliancePolicy -RemoveExisting -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*Policies*'
            }
        }

        It 'Should only delete policies with hydration marker' {
            Mock Test-HydrationKitObject {
                param($Description)
                return $Description -like '*Imported by Intune Hydration Kit*'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'policy-1'; displayName = 'Hydration Policy'; description = 'Imported by Intune Hydration Kit' },
                            @{ id = 'policy-2'; displayName = 'Manual Policy'; description = 'Created manually' }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -RemoveExisting -WhatIf

            $deletedPolicies = $result | Where-Object { $_.Action -eq 'WouldDelete' }
            $deletedPolicies.Count | Should -Be 1
            $deletedPolicies[0].Name | Should -Be 'Hydration Policy'
        }

        It 'Should delete policies when RemoveExisting is specified' {
            Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'policy-1'; displayName = 'Test Policy'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }
                if ($Method -eq 'DELETE') {
                    return $null
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -RemoveExisting -Confirm:$false

            $deletedItems = @($result | Where-Object { $_.Action -eq 'Deleted' })
            $deletedItems.Count | Should -Be 1
            $deletedItems[0].Name | Should -Be 'Test Policy'
        }
    }

    Context 'Error Handling' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Compliance.json'; Name = 'Windows-Compliance.json' })
            } -ModuleName IntuneHydrationKit
        }

        It 'Should handle API errors gracefully' {
            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.windows10CompliancePolicy", "displayName": "Test Policy"}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
                if ($Method -eq 'POST') { throw "API Error" }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result[0].Action | Should -Be 'Failed'
        }

        It 'Should return empty array when no templates found' {
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result | Should -BeNullOrEmpty
        }

        It 'Should handle missing displayName in template' {
            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.windows10CompliancePolicy"}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Missing displayName*'
        }
    }

    Context 'Platform Filtering' {
        It 'Should pass platform parameter to Get-FilteredTemplates' {
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit

            Import-IntuneCompliancePolicy -Platform Windows

            Should -Invoke Get-FilteredTemplates -ModuleName IntuneHydrationKit -ParameterFilter {
                $Platform -contains 'Windows'
            }
        }
    }

    Context 'Result Structure' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Compliance.json'; Name = 'Windows-Compliance.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.windows10CompliancePolicy", "displayName": "Test Policy", "description": ""}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
                return @{ id = 'policy-123'; displayName = 'Test Policy' }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return results with correct structure' {
            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be 'Test Policy'
            $result[0].Type | Should -Be 'CompliancePolicy'
            $result[0].Action | Should -Be 'Created'
        }
    }
}
