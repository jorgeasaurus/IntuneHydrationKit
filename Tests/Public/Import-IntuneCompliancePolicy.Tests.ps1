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
                param($Method)
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
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(@{ id = 'existing-id'; displayName = '[IHD] Windows 10 Compliance Policy'; description = 'Existing policy' }) }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Skipped'
        }

        It 'Should create policy when existing object with same name is not tagged by kit' {
            Mock Test-HydrationKitObject { return $false } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(@{ id = 'existing-id'; displayName = '[IHD] Windows 10 Compliance Policy'; description = 'Manually created policy' }) }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldCreate'
        }

        It 'Should create policy if it does not exist' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-policy-id'; displayName = 'Windows 10 Compliance Policy' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Created'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*$batch*'
            }
        }

        It 'Should append hydration marker to description' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    # Body is a JSON batch envelope; verify the nested policy description
                    $batchObj = $Body | ConvertFrom-Json
                    $batchObj.requests[0].body.description | Should -BeLike '*Imported by Intune Hydration Kit*'
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-policy-id'; displayName = '[IHD] Windows 10 Compliance Policy' } }
                        )
                    }
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
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    # Verify the batch contains a request to compliancePolicies endpoint
                    $Body | Should -BeLike '*compliancePolicies*'
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-policy-id'; name = 'Linux Compliance Policy' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneCompliancePolicy -Platform Linux

            # Linux uses /compliancePolicies (not /deviceCompliancePolicies) - verified in batch body
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*$batch*'
            }
        }
    }

    Context 'Create Mode - Custom Compliance Policy Scripts' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @(
                    [PSCustomObject]@{ FullName = 'TestPath\Custom-A.json'; Name = 'Custom-A.json' }
                    [PSCustomObject]@{ FullName = 'TestPath\Custom-B.json'; Name = 'Custom-B.json' }
                )
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                param($Path)
                if ($Path -like '*Custom-A.json') {
                    @{
                        '@odata.type'                          = '#microsoft.graph.windows10CompliancePolicy'
                        displayName                            = 'Custom Policy A'
                        description                            = 'Custom policy A'
                        deviceCompliancePolicyScript           = @{}
                        deviceCompliancePolicyScriptDefinition = @{
                            displayName                  = 'Shared Compliance Script'
                            description                  = 'Shared script'
                            detectionScriptContentBase64 = 'ZGV0ZWN0aW9u'
                            enforceSignatureCheck        = $false
                            runAs32Bit                   = $false
                            runAsAccount                 = 'system'
                            rules                        = @(
                                @{
                                    property = 'ComplianceState'
                                    operator = 'equals'
                                    value    = 'Compliant'
                                }
                            )
                        }
                    } | ConvertTo-Json -Depth 10
                } else {
                    @{
                        '@odata.type'                          = '#microsoft.graph.windows10CompliancePolicy'
                        displayName                            = 'Custom Policy B'
                        description                            = 'Custom policy B'
                        deviceCompliancePolicyScript           = @{}
                        deviceCompliancePolicyScriptDefinition = @{
                            displayName                  = 'Shared Compliance Script'
                            description                  = 'Shared script'
                            detectionScriptContentBase64 = 'ZGV0ZWN0aW9u'
                            enforceSignatureCheck        = $false
                            runAs32Bit                   = $false
                            runAsAccount                 = 'system'
                            rules                        = @(
                                @{
                                    property = 'ComplianceState'
                                    operator = 'equals'
                                    value    = 'Compliant'
                                }
                            )
                        }
                    } | ConvertTo-Json -Depth 10
                }
            } -ModuleName IntuneHydrationKit

            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                if ($Uri -like '*deviceComplianceScripts*' -and $ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'existing-script-id'; displayName = 'Shared Compliance Script' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST' -and $Uri -eq 'beta/deviceManagement/deviceCompliancePolicies') {
                    return @{ id = 'created-policy-id' }
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should prefetch compliance scripts once and reuse them for custom policies' {
            $result = Import-IntuneCompliancePolicy -Platform Windows

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 2
            Should -Invoke Get-GraphPagedResults -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -like '*deviceComplianceScripts*'
            } -Times 1
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'beta/deviceManagement/deviceComplianceScripts'
            } -Times 0
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
                param($Method)
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
                param($Method)
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
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 204 }
                        )
                    }
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
                param($Method, $Uri)
                if ($Method -eq 'GET') { return @{ value = @() } }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'policy-123'; displayName = 'Test Policy' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return results with correct structure' {
            $result = Import-IntuneCompliancePolicy -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be '[IHD] Test Policy'
            $result[0].Type | Should -Be 'CompliancePolicy'
            $result[0].Action | Should -Be 'Created'
        }
    }
}
