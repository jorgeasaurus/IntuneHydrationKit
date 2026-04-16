#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Import-IntuneAppProtectionPolicy' {
    BeforeAll {
        # Catch-all mock prevents real Graph API calls (which would hang on auth)
        Mock Invoke-MgGraphRequest { return @{ value = @() } } -ModuleName IntuneHydrationKit
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit
        Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit
    }

    Context 'Parameter Validation' {
        It 'Should have TemplatePath parameter' {
            $command = Get-Command Import-IntuneAppProtectionPolicy
            $param = $command.Parameters['TemplatePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have Platform parameter with ValidateSet' {
            $command = Get-Command Import-IntuneAppProtectionPolicy
            $param = $command.Parameters['Platform']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'iOS'
            $validateSet.ValidValues | Should -Contain 'Android'
            $validateSet.ValidValues | Should -Contain 'All'
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Import-IntuneAppProtectionPolicy
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneAppProtectionPolicy
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Template Loading' {
        It 'Should return empty array when template directory does not exist' {
            $result = Import-IntuneAppProtectionPolicy -TemplatePath 'TestDrive:\NonExistent'

            $result | Should -BeNullOrEmpty
        }

        It 'Should return empty array when no templates found' {
            New-Item -Path 'TestDrive:\EmptyAppProtection' -ItemType Directory -Force | Out-Null

            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneAppProtectionPolicy -TemplatePath 'TestDrive:\EmptyAppProtection'

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Create Mode - Android Policy' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Android-AppProtection.json'
                        Name     = 'Android-AppProtection.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.androidManagedAppProtection",
    "displayName": "Android MAM Policy",
    "description": "Test Android app protection"
}
'@
            } -ModuleName IntuneHydrationKit

            Mock Copy-DeepObject {
                param($InputObject)
                return $InputObject
            } -ModuleName IntuneHydrationKit

            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
            Mock New-HydrationDescription { return "Imported by Intune Hydration Kit" } -ModuleName IntuneHydrationKit
        }

        It 'Should skip policy if it already exists and is tagged' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @(@{
                                id          = 'existing-id'
                                displayName = '[IHD] Android MAM Policy'
                                description = 'Imported by Intune Hydration Kit'
                            }) 
                    }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneAppProtectionPolicy

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' })
            $skipped.Count | Should -BeGreaterOrEqual 1
        }

        It 'Should create policy when it does not exist' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Android MAM Policy'; Type = 'AppProtection'; Action = 'Created'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneAppProtectionPolicy

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 1
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\iOS-AppProtection.json'; Name = 'iOS-AppProtection.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.iosManagedAppProtection", "displayName": "iOS MAM Policy", "description": ""}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
            Mock New-HydrationDescription { return "Imported by Intune Hydration Kit" } -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate action when WhatIf is specified' {
            $result = Import-IntuneAppProtectionPolicy -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldCreate'
        }

        It 'Should not call batch operation when WhatIf is specified' {
            Mock Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit

            Import-IntuneAppProtectionPolicy -WhatIf

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
        }
    }

    Context 'Delete Mode' {
        BeforeAll {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Android-AppProtection.json'; Name = 'Android-AppProtection.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.androidManagedAppProtection", "displayName": "Test Policy"}'
            } -ModuleName IntuneHydrationKit
        }

        It 'Should only delete policies with hydration marker and matching template names' {
            Mock Test-HydrationKitObject {
                param($Description, $ObjectName)
                return $Description -like '*Imported by Intune Hydration Kit*'
            } -ModuleName IntuneHydrationKit

            Mock Get-TemplateDisplayNames {
                $hashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $hashSet.Add('Test Policy') | Out-Null
                return $hashSet
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' },
                            @{ id = 'policy-2'; displayName = 'Manual Policy'; description = 'Created manually' }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Test Policy'; Type = 'AppProtection'; Action = 'Deleted'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneAppProtectionPolicy -RemoveExisting -Confirm:$false

            $deleted = @($result | Where-Object { $_.Action -eq 'Deleted' })
            $deleted.Count | Should -Be 1
            $deleted[0].Name | Should -Be '[IHD] Test Policy'
        }

        It 'Should return WouldDelete in WhatIf mode' {
            Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit

            Mock Get-TemplateDisplayNames {
                $hashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $hashSet.Add('Test Policy') | Out-Null
                return $hashSet
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneAppProtectionPolicy -RemoveExisting -WhatIf

            $wouldDelete = @($result | Where-Object { $_.Action -eq 'WouldDelete' })
            $wouldDelete.Count | Should -Be 1
        }
    }

    Context 'Error Handling' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Android-Bad.json'; Name = 'Android-Bad.json' })
            } -ModuleName IntuneHydrationKit
        }

        It 'Should handle template with missing displayName or @odata.type' {
            Mock Get-Content { '{"description": "missing required fields"}' } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneAppProtectionPolicy

            $failed = @($result | Where-Object { $_.Action -eq 'Failed' })
            $failed.Count | Should -Be 1
            $failed[0].Status | Should -BeLike '*Missing displayName*'
        }
    }
}
