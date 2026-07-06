#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Import-CISBaseline delete mode' {
    BeforeAll {
        Mock Invoke-MgGraphRequest { return @{ value = @() } } -ModuleName IntuneHydrationKit
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit
        Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit

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

    It 'Should throw when delete mode cannot resolve a valid baseline path' {
        InModuleScope IntuneHydrationKit {
            $script:HydrationState = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Connected = $true }
            $script:TemplatesPath = 'TestDrive:\NonExistent'
            $script:ModuleRoot = 'TestDrive:\NonExistent'
        }

        Mock Test-Path { return $false } -ModuleName IntuneHydrationKit

        { Import-CISBaseline -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -ErrorAction Stop } | Should -Throw '*A resolvable CIS baseline template path is required when using -RemoveExisting*'
    }

    It 'Should throw when delete mode cannot load template names' {
        Mock Invoke-GraphBatchOperation { } -ModuleName IntuneHydrationKit

        { Import-CISBaseline -BaselinePath (Join-Path 'TestDrive:' 'CISDelete') -Platform Linux -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -Confirm:$false -ErrorAction Stop } | Should -Throw '*Deletion is blocked to avoid removing hydration-marked objects without template matching*'
        Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
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

    It 'Should exclude no-platform CIS templates outside the selected delete platform' {
        $platformDeleteDir = Join-Path 'TestDrive:' 'CISDeletePlatformInference'
        $windowsComplianceDir = Join-Path $platformDeleteDir '8.0 - Windows 11 Benchmarks'
        $windowsConfigDir = Join-Path $platformDeleteDir '3.0 - Browser Benchmarks'
        $macComplianceDir = Join-Path $platformDeleteDir '2.0 - Apple Benchmarks/Apple MacOS Compliance'
        New-Item -Path $windowsComplianceDir -ItemType Directory -Force | Out-Null
        New-Item -Path $windowsConfigDir -ItemType Directory -Force | Out-Null
        New-Item -Path $macComplianceDir -ItemType Directory -Force | Out-Null

        Set-Content -Path (Join-Path $windowsComplianceDir 'WindowsCompliance.json') -Value (@{
                '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'
                displayName   = 'Windows Compliance Without Platforms'
                description   = ''
            } | ConvertTo-Json)
        Set-Content -Path (Join-Path $windowsConfigDir 'WindowsConfig.json') -Value (@{
                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
                name          = 'Windows Config Without Platforms'
                description   = ''
                settings      = @()
            } | ConvertTo-Json)
        Set-Content -Path (Join-Path $macComplianceDir 'MacCompliance.json') -Value (@{
                '@odata.type' = '#microsoft.graph.macOSCompliancePolicy'
                displayName   = 'macOS Compliance Without Platforms'
                description   = ''
            } | ConvertTo-Json)

        Mock Get-GraphPagedResults {
            param($Uri)

            if ($Uri -eq 'beta/deviceManagement/deviceCompliancePolicies') {
                return @(
                    @{ id = 'win-compliance'; displayName = '[IHD] Windows Compliance Without Platforms'; description = 'Imported by Intune Hydration Kit' }
                    @{ id = 'mac-compliance'; displayName = '[IHD] macOS Compliance Without Platforms'; description = 'Imported by Intune Hydration Kit' }
                )
            }

            if ($Uri -eq 'beta/deviceManagement/configurationPolicies') {
                return @(
                    @{ id = 'win-config'; name = '[IHD] Windows Config Without Platforms'; description = 'Imported by Intune Hydration Kit' }
                )
            }

            return @()
        } -ModuleName IntuneHydrationKit

        $script:capturedCISDeleteItems = @()
        Mock Invoke-GraphBatchOperation {
            param($Items)
            $script:capturedCISDeleteItems = @($Items)
            return @($Items | ForEach-Object {
                    [PSCustomObject]@{ Name = $_.Name; Type = 'CISBaselinePolicy'; Action = 'Deleted'; Status = 'Success' }
                })
        } -ModuleName IntuneHydrationKit

        Import-CISBaseline -BaselinePath $platformDeleteDir -Platform macOS -RemoveExisting -TenantId '00000000-0000-0000-0000-000000000001' -Confirm:$false | Out-Null

        $script:capturedCISDeleteItems | Should -HaveCount 1
        $script:capturedCISDeleteItems[0].Name | Should -Be '[IHD] macOS Compliance Without Platforms'
    }
}
