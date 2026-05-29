#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Import-IntuneBaseline' {
    BeforeAll {
        # Catch-all mock prevents real Graph API calls (which would hang on auth)
        Mock Invoke-MgGraphRequest { return @{ value = @() } } -ModuleName IntuneHydrationKit
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit
        Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit
        Mock New-HydrationDescription { return "Imported by Intune Hydration Kit" } -ModuleName IntuneHydrationKit
    }

    Context 'Parameter Validation' {
        It 'Should have BaselinePath parameter' {
            $command = Get-Command Import-IntuneBaseline
            $param = $command.Parameters['BaselinePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have Platform parameter with ValidateSet' {
            $command = Get-Command Import-IntuneBaseline
            $param = $command.Parameters['Platform']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Windows'
            $validateSet.ValidValues | Should -Contain 'macOS'
            $validateSet.ValidValues | Should -Contain 'iOS'
            $validateSet.ValidValues | Should -Contain 'Android'
            $validateSet.ValidValues | Should -Contain 'All'
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Import-IntuneBaseline
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneBaseline
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

            { Import-IntuneBaseline -ErrorAction Stop } | Should -Throw '*TenantId is required*'
        }
    }

    Context 'Missing BaselinePath' {
        It 'Should throw terminating error when baseline templates not found' {
            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:TemplatesPath = 'TestDrive:\NonExistent'
                $script:ModuleRoot = 'TestDrive:\NonExistent'
            }

            # Mock Test-Path to return false for any OpenIntuneBaseline path resolution
            Mock Test-Path {
                return $false
            } -ModuleName IntuneHydrationKit

            { Import-IntuneBaseline -TenantId '00000000-0000-0000-0000-000000000001' -ErrorAction Stop } | Should -Throw '*not found*'
        }
    }

    Context 'Platform Filtering' {
        BeforeAll {
            # Build folder structure for platform filtering test
            $baseDir = Join-Path 'TestDrive:' 'BaselineTemplates'
            New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
            foreach ($osDir in @('WINDOWS', 'MACOS', 'BYOD')) {
                $imDir = Join-Path $baseDir "$osDir\IntuneManagement"
                New-Item -Path $imDir -ItemType Directory -Force | Out-Null
                $policyJson = @{
                    '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                    displayName   = "$osDir Test Policy"
                    description   = ''
                } | ConvertTo-Json
                Set-Content -Path (Join-Path $imDir 'TestPolicy.json') -Value $policyJson
            }

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Invoke-GraphBatchOperation { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should only process Windows folders when -Platform Windows' {
            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'BaselineTemplates') -Platform Windows -TenantId '00000000-0000-0000-0000-000000000001'

            $resultTypes = $result | ForEach-Object { $_.Type }
            $resultTypes | Should -Not -Contain 'MACOS/IntuneManagement'
            $resultTypes | Should -Not -Contain 'BYOD/IntuneManagement'
        }

        It 'Should log cache and preparation progress during import' {
            Mock Invoke-GraphBatchOperation { return @() } -ModuleName IntuneHydrationKit

            Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'BaselineTemplates') -Platform Windows -TenantId '00000000-0000-0000-0000-000000000001' | Out-Null

            Should -Invoke Write-HydrationLog -ModuleName IntuneHydrationKit -ParameterFilter {
                $Message -like 'Discovered * OpenIntuneBaseline templates across * folders'
            }
            Should -Invoke Write-HydrationLog -ModuleName IntuneHydrationKit -ParameterFilter {
                $Message -like 'Caching existing policies (*): *'
            }
            Should -Invoke Write-HydrationLog -ModuleName IntuneHydrationKit -ParameterFilter {
                $Message -eq 'Caching complete. Preparing OpenIntuneBaseline payloads...'
            }
            Should -Invoke Write-HydrationLog -ModuleName IntuneHydrationKit -ParameterFilter {
                $Message -like 'Preparing OpenIntuneBaseline folder (*): */* (* templates)'
            }
            Should -Invoke Write-HydrationLog -ModuleName IntuneHydrationKit -ParameterFilter {
                $Message -like 'Prepared * OpenIntuneBaseline payloads. Starting batch import...'
            }
        }

        It 'Should scope BYOD app protection templates and cache endpoints by selected platform' {
            $baseDir = Join-Path 'TestDrive:' 'ByodBaseline'
            $appProtectionDir = Join-Path $baseDir 'BYOD\AppProtection'
            New-Item -Path $appProtectionDir -ItemType Directory -Force | Out-Null

            @{
                '@odata.type' = '#microsoft.graph.iosManagedAppProtection'
                displayName   = 'iOS BYOD Policy'
                description   = ''
            } | ConvertTo-Json | Set-Content -Path (Join-Path $appProtectionDir 'iOS-BYOD.json')

            @{
                '@odata.type' = '#microsoft.graph.androidManagedAppProtection'
                displayName   = 'Android BYOD Policy'
                description   = ''
            } | ConvertTo-Json | Set-Content -Path (Join-Path $appProtectionDir 'Android-BYOD.json')

            Mock Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath $baseDir -Platform iOS -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result.Name | Should -Contain '[IHD] iOS BYOD Policy'
            $result.Name | Should -Not -Contain '[IHD] Android BYOD Policy'
            Should -Invoke Get-GraphPagedResults -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -eq 'beta/deviceAppManagement/iosManagedAppProtections'
            } -Times 1
            Should -Invoke Get-GraphPagedResults -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -eq 'beta/deviceAppManagement/androidManagedAppProtections'
            }
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
        }
    }

    Context 'WhatIf Support' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'WhatIfBaseline'
            $imDir = Join-Path $baseDir 'WINDOWS\IntuneManagement'
            New-Item -Path $imDir -ItemType Directory -Force | Out-Null
            $policyJson = @{
                '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                displayName   = 'WhatIf Test Policy'
                description   = ''
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $imDir 'WhatIfPolicy.json') -Value $policyJson

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate results without calling Graph' {
            Mock Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'WhatIfBaseline') -Platform Windows -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldCreate'
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
        }

        It 'Should skip existing policies in WhatIf mode after checking the cache' {
            Mock Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit
            Mock Get-GraphPagedResults {
                param($ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(@{ displayName = '[IHD] WhatIf Test Policy'; id = 'existing-id' })
                }
                return @()
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'WhatIfBaseline') -Platform Windows -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Skipped'
            $result[0].Status | Should -Be 'Already exists'
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
        }
    }

    Context 'RemoveExisting Mode' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'DeleteBaseline'
            $imDir = Join-Path $baseDir 'WINDOWS\IntuneManagement'
            New-Item -Path $imDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $imDir 'Dummy.json') -Value '{}'

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
                    @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
                )
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Test Policy'; Type = 'BaselinePolicy'; Action = 'Deleted'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'DeleteBaseline') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldDelete in WhatIf mode' {
            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
                )
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'DeleteBaseline') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldDelete'
        }

        It 'Should skip policies not created by this kit' {
            Mock Test-HydrationKitObject { return $false } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'policy-1'; displayName = 'Manual Policy'; description = 'Created manually' }
                )
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'DeleteBaseline') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf

            $result | Should -BeNullOrEmpty
        }

        It 'Should delete prefixed policies when list response omits description but full GET has marker' {
            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'policy-1'; displayName = '[IHD] Test Policy' }
                )
            } -ModuleName IntuneHydrationKit

            Mock Test-HydrationKitObject { return $false } -ModuleName IntuneHydrationKit -ParameterFilter {
                [string]::IsNullOrWhiteSpace($Description) -and [string]::IsNullOrWhiteSpace($Notes)
            }

            Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit -ParameterFilter {
                $Description -like '*Imported by Intune Hydration Kit*'
            }

            Mock Invoke-MgGraphRequest {
                return @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
            } -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/deviceConfigurations/policy-1'
            }

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Test Policy'; Type = 'BaselinePolicy'; Action = 'Deleted'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'DeleteBaseline') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/deviceConfigurations/policy-1'
            }
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit
        }

        It 'Should not delete hydration-tagged policies that are not in OpenIntuneBaseline templates' {
            Mock Get-GraphPagedResults {
                return @(
                    @{ id = 'cis-policy-1'; displayName = '[IHD] CIS Windows Policy'; description = 'Imported by Intune Hydration Kit' }
                )
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation { @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'DeleteBaseline') -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -Confirm:$false

            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
        }
    }

    Context 'IntuneManagement Folder Routing' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'RoutingBaseline'
            $imDir = Join-Path $baseDir 'WINDOWS\IntuneManagement'
            New-Item -Path $imDir -ItemType Directory -Force | Out-Null
            $policyJson = @{
                '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                displayName   = 'Device Config Policy'
                description   = 'Test device configuration'
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $imDir 'DeviceConfig.json') -Value $policyJson

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Get-GraphPagedResults { return @() } -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should route IntuneManagement policies by @odata.type' {
            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{ Name = $item.Name; Type = 'BaselinePolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'RoutingBaseline') -TenantId '00000000-0000-0000-0000-000000000001'

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -ParameterFilter {
                $Items[0].Url -like '*/deviceConfigurations*'
            }
        }

        It 'Should skip policy with unsupported @odata.type' {
            $unsupportedDir = Join-Path 'TestDrive:' 'UnsupportedType\WINDOWS\IntuneManagement'
            New-Item -Path $unsupportedDir -ItemType Directory -Force | Out-Null
            $unsupportedJson = @{
                '@odata.type' = '#microsoft.graph.unsupportedType'
                displayName   = 'Unsupported Policy'
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $unsupportedDir 'Unsupported.json') -Value $unsupportedJson

            Mock Invoke-GraphBatchOperation { return @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'UnsupportedType') -TenantId '00000000-0000-0000-0000-000000000001'

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' })
            $skipped.Count | Should -BeGreaterOrEqual 1
            $skipped[0].Status | Should -BeLike '*Unsupported*'
        }
    }

    Context 'Existing Policy Skip' {
        BeforeAll {
            $baseDir = Join-Path 'TestDrive:' 'SkipBaseline'
            $imDir = Join-Path $baseDir 'WINDOWS\IntuneManagement'
            New-Item -Path $imDir -ItemType Directory -Force | Out-Null
            $policyJson = @{
                '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                displayName   = 'Existing Policy'
                description   = ''
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $imDir 'Existing.json') -Value $policyJson

            InModuleScope IntuneHydrationKit {
                $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
                $script:ImportPrefix = '[IHD] '
            }

            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
            Mock Remove-ReadOnlyGraphProperties -ModuleName IntuneHydrationKit
        }

        It 'Should skip policies that already exist in tenant' {
            Mock Get-GraphPagedResults {
                param($ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(@{ displayName = '[IHD] Existing Policy'; id = 'existing-id' })
                }
                return @()
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation { return @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath (Join-Path 'TestDrive:' 'SkipBaseline') -TenantId '00000000-0000-0000-0000-000000000001'

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Status -eq 'Already exists' })
            $skipped.Count | Should -BeGreaterOrEqual 1
        }
    }
}
