#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Import-CISBaseline' {
    BeforeAll {
        # Catch-all mock prevents real Graph API calls
        Mock Invoke-MgGraphRequest { return @{ value = @() } } -ModuleName IntuneHydrationKit
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit
        Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit
        Mock New-HydrationDescription { return "Imported by Intune Hydration Kit" } -ModuleName IntuneHydrationKit
    }

    Context 'Parameter Validation' {
        It 'Should have BaselinePath parameter' {
            $command = Get-Command Import-CISBaseline
            $param = $command.Parameters['BaselinePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have Platform parameter with ValidateSet including Linux' {
            $command = Get-Command Import-CISBaseline
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
            $command = Get-Command Import-CISBaseline
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-CISBaseline
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Missing TenantId' {
        It 'Should throw terminating error when TenantId is not provided and not connected' {
            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = $null; Connected = $false }
                $script:TemplatesPath = 'TestDrive:\Templates'
            }

            { Import-CISBaseline -ErrorAction Stop } | Should -Throw '*TenantId is required*'
        }
    }

    Context 'Missing BaselinePath' {
        It 'Should throw terminating error when CIS baseline templates not found' {
            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:TemplatesPath = 'TestDrive:\NonExistent'
                $script:ModuleRoot = 'TestDrive:\NonExistent'
            }

            Mock Test-Path {
                return $false
            } -ModuleName IntuneHydrationKit

            { Import-CISBaseline -TenantId '00000000-0000-0000-0000-000000000001' -ErrorAction Stop } | Should -Throw '*not found*'
        }
    }

    Context 'Flat Folder Traversal' {
        BeforeAll {
            # Build flat CIS baseline folder structure: category/policy.json
            $baseDir = Join-Path 'TestDrive:' 'CISBaselines'
            New-Item -Path $baseDir -ItemType Directory -Force | Out-Null

            $androidDir = Join-Path $baseDir '1.0 - Android Benchmarks'
            New-Item -Path $androidDir -ItemType Directory -Force | Out-Null
            $androidPolicy = @{
                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                name          = 'Android Test Policy'
                description   = ''
                platforms     = 'androidEnterprise'
                technologies  = 'android'
                settings      = @()
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $androidDir 'AndroidPolicy.json') -Value $androidPolicy

            $windowsDir = Join-Path $baseDir '8.0 - Windows 11 Benchmarks'
            New-Item -Path $windowsDir -ItemType Directory -Force | Out-Null
            $windowsPolicy = @{
                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                name          = 'Windows Test Policy'
                description   = ''
                platforms     = 'windows10'
                technologies  = 'mdm'
                settings      = @()
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $windowsDir 'WindowsPolicy.json') -Value $windowsPolicy

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Invoke-GraphBatchOperation { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should discover policies from flat category folders' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISBaselines') -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $Items.Count -eq 2
            }
        }

        It 'Should route all policies to configurationPolicies endpoint' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISBaselines') -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $Items | ForEach-Object { $_.Url -like '*/configurationPolicies*' } | Where-Object { $_ -eq $true } | Measure-Object | Select-Object -ExpandProperty Count
            }
        }
    }

    Context 'Platform Filtering' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISPlatformFilter'
            New-Item -Path $baseDir -ItemType Directory -Force | Out-Null

            $androidDir = Join-Path $baseDir '1.0 - Android Benchmarks'
            New-Item -Path $androidDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $androidDir 'Android.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'Android CIS Policy'
                    description   = ''
                    platforms     = 'androidEnterprise'
                    technologies  = 'android'
                    settings      = @()
                } | ConvertTo-Json)

            $windowsDir = Join-Path $baseDir '8.0 - Windows Benchmarks'
            New-Item -Path $windowsDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $windowsDir 'Windows.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'Windows CIS Policy'
                    description   = ''
                    platforms     = 'windows10'
                    technologies  = 'mdm'
                    settings      = @()
                } | ConvertTo-Json)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should only import Windows policies when -Platform Windows' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISPlatformFilter') -Platform Windows -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $Items.Count -eq 1 -and $Items[0].Name -like '*Windows*'
            }
        }
    }

    Context 'WhatIf Support' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISWhatIf'
            $catDir = Join-Path $baseDir '1.0 - Test Category'
            New-Item -Path $catDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $catDir 'TestPolicy.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'WhatIf CIS Policy'
                    description   = ''
                    platforms     = 'windows10'
                    technologies  = 'mdm'
                    settings      = @()
                } | ConvertTo-Json)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate results without calling Graph' {
            Mock Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISWhatIf') -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldCreate'
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
        }
    }

    Context 'RemoveExisting Mode' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISDelete'
            $catDir = Join-Path $baseDir '1.0 - Test Category'
            New-Item -Path $catDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $catDir 'Dummy.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'Test Policy'
                    description   = ''
                    platforms     = 'windows10'
                    technologies  = 'mdm'
                    settings      = @()
                } | ConvertTo-Json)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-TemplateDisplayNames {
                $hashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $hashSet.Add('Test Policy') | Out-Null
                return $hashSet
            } -ModuleName IntuneHydrationKit
        }

        It 'Should delete tagged policies and return results' {
            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'policy-1'; name = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
                )
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Test Policy'; Type = 'CISBaselinePolicy'; Action = 'Deleted'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISDelete') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldDelete in WhatIf mode' {
            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'policy-1'; name = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
                )
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISDelete') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldDelete'
        }

        It 'Should skip policies not created by this kit' {
            Mock Test-HydrationKitObject { return $false } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'policy-1'; name = 'Manual Policy'; description = 'Created manually' }
                )
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISDelete') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result | Should -BeNullOrEmpty
        }

        It 'Should delete prefixed policies when list response omits description but full GET has marker' {
            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'policy-1'; name = '[IHD] Test Policy' }
                )
            } -ModuleName IntuneHydrationKit

            Mock Test-HydrationKitObject { return $false } -ModuleName IntuneHydrationKit -ParameterFilter {
                [string]::IsNullOrWhiteSpace($Description) -and [string]::IsNullOrWhiteSpace($Notes)
            }

            Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit -ParameterFilter {
                $Description -like '*Imported by Intune Hydration Kit*'
            }

            Mock Invoke-MgGraphRequest {
                return @{ id = 'policy-1'; name = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
            } -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/configurationPolicies/policy-1'
            }

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Test Policy'; Type = 'CISBaselinePolicy'; Action = 'Deleted'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISDelete') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/configurationPolicies/policy-1'
            }
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit
        }
    }

    Context 'Unsupported @odata.type' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISUnsupported'
            $catDir = Join-Path $baseDir '1.0 - Test Category'
            New-Item -Path $catDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $catDir 'Unsupported.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.unsupportedType'
                    displayName   = 'Unsupported Policy'
                    description   = ''
                } | ConvertTo-Json)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Invoke-GraphBatchOperation { return @() } -ModuleName IntuneHydrationKit
        }

        It 'Should skip policy with unsupported @odata.type' {
            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISUnsupported') -TenantId '00000000-0000-0000-0000-000000000001'

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' })
            $skipped.Count | Should -BeGreaterOrEqual 1
            $skipped[0].Status | Should -BeLike '*Unsupported*'
        }
    }

    Context 'Additional supported odata types' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISAdditionalTypes'
            $catDir = Join-Path $baseDir '1.0 - Mixed Category'
            New-Item -Path $catDir -ItemType Directory -Force | Out-Null

            Set-Content -Path (Join-Path $catDir 'GroupPolicy.json') -Value (@{
                    '@odata.type'    = '#microsoft.graph.groupPolicyConfiguration'
                    displayName      = 'Administrative Template Policy'
                    description      = ''
                    definitionValues = @()
                } | ConvertTo-Json -Depth 10)

            Set-Content -Path (Join-Path $catDir 'Intent.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementIntent'
                    displayName   = 'Endpoint Security Policy'
                    description   = ''
                    templateId    = 'template-1'
                    settings      = @()
                } | ConvertTo-Json -Depth 10)

            Set-Content -Path (Join-Path $catDir 'LinuxCompliance.json') -Value (@{
                    '@odata.type'           = '#microsoft.graph.deviceManagementCompliancePolicy'
                    name                    = 'Linux Compliance Policy'
                    description             = ''
                    platforms               = 'linux'
                    technologies            = 'linuxMdm'
                    settings                = @()
                    scheduledActionsForRule = @()
                } | ConvertTo-Json -Depth 10)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should route supported non-configuration CIS templates to their Graph endpoints' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISAdditionalTypes') -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $Items.Count -eq 3 -and
                ($Items.Url -contains '/deviceManagement/groupPolicyConfigurations') -and
                ($Items.Url -contains '/deviceManagement/intents') -and
                ($Items.Url -contains '/deviceManagement/compliancePolicies')
            }
        }
    }

    Context 'Existing Policy Skip' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISSkip'
            $catDir = Join-Path $baseDir '1.0 - Test Category'
            New-Item -Path $catDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $catDir 'Existing.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'Existing Policy'
                    description   = ''
                    platforms     = 'windows10'
                    technologies  = 'mdm'
                    settings      = @()
                } | ConvertTo-Json)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should skip policies that already exist in tenant' {
            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(@{ name = '[IHD] Existing Policy'; id = 'existing-id' })
                }
                return @()
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation { return @() } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISSkip') -TenantId '00000000-0000-0000-0000-000000000001'

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Status -eq 'Already exists' })
            $skipped.Count | Should -BeGreaterOrEqual 1
        }

        It 'Should create policy when cached existing item returns 404 on verify' {
            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(@{ name = '[IHD] Existing Policy'; id = 'existing-id' })
                }
                return @()
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                throw [System.Exception]::new('404 NotFound')
            } -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/configurationPolicies/existing-id'
            }

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Existing Policy'; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISSkip') -TenantId '00000000-0000-0000-0000-000000000001'

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 1
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 1
        }
    }

    Context 'Missing @odata.type inference' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISMissingODataType'
            $catDir = Join-Path $baseDir '3.0 - Browser Benchmarks'
            New-Item -Path $catDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $catDir 'MissingODataType.json') -Value (@{
                    '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#deviceManagement/configurationPolicies/$entity'
                    name             = 'Missing OData Type Policy'
                    description      = ''
                    platforms        = 'windows10'
                    technologies     = 'mdm'
                    settings         = @()
                } | ConvertTo-Json)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should import configuration policy templates that omit @odata.type' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISMissingODataType') -TenantId '00000000-0000-0000-0000-000000000001'

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 1
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $Items.Count -eq 1 -and $Items[0].Url -eq '/deviceManagement/configurationPolicies'
            }
        }
    }

    Context 'Secret setting normalization' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISSecretSettings'
            $catDir = Join-Path $baseDir '8.0 - Windows 11 Benchmarks'
            New-Item -Path $catDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $catDir 'SecretPolicy.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'Secret-backed policy'
                    description   = ''
                    platforms     = 'windows10'
                    technologies  = 'mdm'
                    settings      = @(
                        @{
                            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                            id              = '0'
                            settingInstance = @{
                                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                settingDefinitionId = 'choice_parent'
                                choiceSettingValue  = @{
                                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                                    value         = 'choice_parent_enabled'
                                    children      = @(
                                        @{
                                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                            settingDefinitionId = 'contoso_networkcredentials_password'
                                            simpleSettingValue  = @{
                                                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'
                                                value         = 'top-secret'
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    )
                } | ConvertTo-Json -Depth 20)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should convert password-like string settings to secret setting values' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISSecretSettings') -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $body = $Items[0].BodyJson | ConvertFrom-Json -Depth 50
                $secretValue = $body.settings[0].settingInstance.choiceSettingValue.children[0].simpleSettingValue
                $secretValue.'@odata.type' -eq '#microsoft.graph.deviceManagementConfigurationSecretSettingValue' -and
                $secretValue.valueState -eq 'notEncrypted'
            }
        }

        It 'Should convert terminal segment names like networkpassword to secret values' {
            Set-Content -Path (Join-Path 'TestDrive:\CISSecretSettings\8.0 - Windows 11 Benchmarks' 'TerminalSegmentSecretPolicy.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'Terminal segment secret policy'
                    description   = ''
                    platforms     = 'windows10'
                    technologies  = 'mdm'
                    settings      = @(
                        @{
                            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                            id              = '2'
                            settingInstance = @{
                                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                settingDefinitionId = 'choice_parent'
                                choiceSettingValue  = @{
                                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                                    value         = 'choice_parent_enabled'
                                    children      = @(
                                        @{
                                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                            settingDefinitionId = 'contoso_networkpassword'
                                            simpleSettingValue  = @{
                                                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'
                                                value         = 'top-secret'
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    )
                } | ConvertTo-Json -Depth 20)

            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $null = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISSecretSettings') -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $body = $Items | Where-Object { $_.Name -eq '[IHD] Terminal segment secret policy' } | Select-Object -First 1 | ForEach-Object { $_.BodyJson | ConvertFrom-Json -Depth 50 }
                $secretValue = $body.settings[0].settingInstance.choiceSettingValue.children[0].simpleSettingValue
                $secretValue.'@odata.type' -eq '#microsoft.graph.deviceManagementConfigurationSecretSettingValue' -and
                $secretValue.valueState -eq 'notEncrypted'
            }
        }

        It 'Should not convert settings that only contain password as part of a longer token' {
            Set-Content -Path (Join-Path 'TestDrive:\CISSecretSettings\8.0 - Windows 11 Benchmarks' 'NonSecretPolicy.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                    name          = 'Non-secret password-adjacent policy'
                    description   = ''
                    platforms     = 'windows10'
                    technologies  = 'mdm'
                    settings      = @(
                        @{
                            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                            id              = '1'
                            settingInstance = @{
                                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                settingDefinitionId = 'choice_parent'
                                choiceSettingValue  = @{
                                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                                    value         = 'choice_parent_enabled'
                                    children      = @(
                                        @{
                                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                            settingDefinitionId = 'contoso_networkpasswordencryptionstore'
                                            simpleSettingValue  = @{
                                                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'
                                                value         = 'plaintext'
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    )
                } | ConvertTo-Json -Depth 20)

            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'CISBaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $null = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISSecretSettings') -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $body = $Items | Where-Object { $_.Name -eq '[IHD] Non-secret password-adjacent policy' } | Select-Object -First 1 | ForEach-Object { $_.BodyJson | ConvertFrom-Json -Depth 50 }
                $plainValue = $body.settings[0].settingInstance.choiceSettingValue.children[0].simpleSettingValue
                $plainValue.'@odata.type' -eq '#microsoft.graph.deviceManagementConfigurationStringSettingValue' -and
                -not $plainValue.PSObject.Properties['valueState']
            }
        }
    }

    Context 'Group policy and nested metadata cleanup' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'CISPayloadCleanup'
            $groupPolicyDir = Join-Path $baseDir '4.0 - CIS Benchmarks'
            $intentDir = Join-Path $baseDir '6.0 - Endpoint Security'
            New-Item -Path $groupPolicyDir -ItemType Directory -Force | Out-Null
            New-Item -Path $intentDir -ItemType Directory -Force | Out-Null

            Set-Content -Path (Join-Path $groupPolicyDir 'VSCode.json') -Value (@{
                    '@odata.type'    = '#microsoft.graph.groupPolicyConfiguration'
                    displayName      = 'VS Code Policy'
                    description      = ''
                    definitionValues = @{
                        enabled                 = $true
                        'definition@odata.bind' = 'https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions(''def-1'')'
                        presentationValues      = @{
                            '@odata.type'             = '#microsoft.graph.groupPolicyPresentationValueText'
                            value                     = 'default'
                            'presentation@odata.bind' = 'https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions(''def-1'')/presentations(''pres-1'')'
                        }
                    }
                } | ConvertTo-Json -Depth 20)

            Set-Content -Path (Join-Path $intentDir 'Bitlocker.json') -Value (@{
                    '@odata.type' = '#microsoft.graph.deviceManagementIntent'
                    displayName   = 'Bitlocker Policy'
                    description   = ''
                    templateId    = 'template-1'
                    settings      = @(
                        @{
                            '@odata.type'                 = '#microsoft.graph.deviceManagementComplexSettingInstance'
                            id                            = 'setting-1'
                            definitionId                  = 'bitlockerPolicy'
                            valueJson                     = '{"encryptionMethod":"xtsAes256"}'
                            'value@odata.associationLink' = 'https://graph.microsoft.com/beta/$ref'
                        }
                    )
                } | ConvertTo-Json -Depth 20)

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return ($InputObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100) } -ModuleName IntuneHydrationKit
        }

        It 'Should normalize singleton definitionValues to an array for group policy payloads' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                $body = $Items | Where-Object { $_.Name -eq '[IHD] VS Code Policy' } | Select-Object -First 1 | ForEach-Object { $_.BodyJson | ConvertFrom-Json -Depth 50 }
                @([PSCustomObject]@{
                        Name   = $body.displayName
                        Type   = 'CISBaselinePolicy'
                        Action = if ($body.definitionValues -is [array] -and $body.definitionValues.Count -eq 1 -and $body.definitionValues[0].presentationValues -is [array]) { 'Created' } else { 'Failed' }
                        Status = 'Success'
                    })
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISPayloadCleanup') -TenantId '00000000-0000-0000-0000-000000000001'

            ($result | Where-Object { $_.Name -eq '[IHD] VS Code Policy' }).Action | Should -Be 'Created'
        }

        It 'Should remove nested invalid odata association links from intent settings' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                $body = $Items | Where-Object { $_.Name -eq '[IHD] Bitlocker Policy' } | Select-Object -First 1 | ForEach-Object { $_.BodyJson | ConvertFrom-Json -Depth 50 }
                $setting = $body.settings[0]
                @([PSCustomObject]@{
                        Name   = $body.displayName
                        Type   = 'CISBaselinePolicy'
                        Action = if (-not $setting.PSObject.Properties['value@odata.associationLink'] -and -not $setting.PSObject.Properties['id']) { 'Created' } else { 'Failed' }
                        Status = 'Success'
                    })
            } -ModuleName IntuneHydrationKit

            $result = Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISPayloadCleanup') -TenantId '00000000-0000-0000-0000-000000000001'

            ($result | Where-Object { $_.Name -eq '[IHD] Bitlocker Policy' }).Action | Should -Be 'Created'
        }
    }
}
