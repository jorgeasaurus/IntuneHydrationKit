#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Import-IntuneConditionalAccessPolicy' {
    BeforeAll {
        # Catch-all mock prevents real Graph API calls (which would hang on auth)
        Mock Invoke-MgGraphRequest { return @{ value = @() } } -ModuleName IntuneHydrationKit
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit

        InModuleScope IntuneHydrationKit {
            $script:TemplatesPath = 'TestDrive:\Templates'
            $script:ImportPrefix = '[IHD] '
        }
    }

    Context 'Parameter Validation' {
        It 'Should have TemplatePath parameter' {
            $command = Get-Command Import-IntuneConditionalAccessPolicy
            $param = $command.Parameters['TemplatePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have Prefix parameter' {
            $command = Get-Command Import-IntuneConditionalAccessPolicy
            $param = $command.Parameters['Prefix']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Import-IntuneConditionalAccessPolicy
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneConditionalAccessPolicy
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Template Path Validation' {
        It 'Should throw terminating error when template path not found' {
            { Import-IntuneConditionalAccessPolicy -TemplatePath 'TestDrive:\NonExistent' -ErrorAction Stop } | Should -Throw '*not found*'
        }
    }

    Context 'Create Mode' {
        BeforeAll {
            # Create template directory and files
            $caDir = Join-Path 'TestDrive:' 'CATemplates'
            New-Item -Path $caDir -ItemType Directory -Force | Out-Null
            $caPolicy = @{
                displayName   = 'Block Legacy Auth'
                state         = 'enabled'
                conditions    = @{ applications = @{ includeApplications = @('All') } }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $caDir 'Block Legacy Auth.json') -Value $caPolicy

            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = (Join-Path 'TestDrive:' 'CATemplates\Block Legacy Auth.json')
                        Name     = 'Block Legacy Auth.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-PremiumP2ServicePlans { return @('AAD_PREMIUM_P2', 'ENTRA_ID_GOVERNANCE') } -ModuleName IntuneHydrationKit
            Mock Test-ConditionalAccessPolicyRequiresP2 { return $false } -ModuleName IntuneHydrationKit
            Mock Test-ConditionalAccessPolicyRequiresPreview { return $null } -ModuleName IntuneHydrationKit
        }

        It 'Should force all policies to disabled state' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*subscribedSkus*') {
                    return @{ value = @(@{ capabilityStatus = 'Enabled'; servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }) }) }
                }
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    $bodyObj = $item.BodyJson | ConvertFrom-Json
                    $bodyObj.state | Should -Be 'disabled'
                    [PSCustomObject]@{ Name = $item.Name; Type = 'ConditionalAccessPolicy'; Action = 'Created'; Status = 'Success' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CATemplates')

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 1
        }

        It 'Should skip policy that already exists' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*subscribedSkus*') {
                    return @{ value = @(@{ capabilityStatus = 'Enabled'; servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }) }) }
                }
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'existing-id'; displayName = '[IHD] Block Legacy Auth'; state = 'disabled' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CATemplates')

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Status -eq 'Already exists' })
            $skipped.Count | Should -Be 1
        }

        It 'Should skip policies requiring P2 when no P2 license' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*subscribedSkus*') {
                    return @{ value = @(@{ capabilityStatus = 'Enabled'; servicePlans = @(@{ servicePlanName = 'BASIC_PLAN'; provisioningStatus = 'Success' }) }) }
                }
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit

            Mock Test-ConditionalAccessPolicyRequiresP2 { return $true } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CATemplates')

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Status -like '*Premium P2*' })
            $skipped.Count | Should -Be 1
        }

        It 'Should skip policies requiring private preview features' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*subscribedSkus*') {
                    return @{ value = @(@{ capabilityStatus = 'Enabled'; servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }) }) }
                }
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit

            Mock Test-ConditionalAccessPolicyRequiresPreview { return 'networkAccess' } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CATemplates')

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Status -like '*preview*' })
            $skipped.Count | Should -Be 1
        }
    }

    Context 'WhatIf Support' {
        BeforeAll {
            $caDir = Join-Path 'TestDrive:' 'CAWhatIf'
            New-Item -Path $caDir -ItemType Directory -Force | Out-Null
            $caPolicy = @{
                displayName   = 'Require MFA'
                state         = 'enabled'
                conditions    = @{ applications = @{ includeApplications = @('All') } }
                grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
            } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $caDir 'Require MFA.json') -Value $caPolicy

            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = (Join-Path 'TestDrive:' 'CAWhatIf\Require MFA.json')
                        Name     = 'Require MFA.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-PremiumP2ServicePlans { return @('AAD_PREMIUM_P2') } -ModuleName IntuneHydrationKit
            Mock Test-ConditionalAccessPolicyRequiresP2 { return $false } -ModuleName IntuneHydrationKit
            Mock Test-ConditionalAccessPolicyRequiresPreview { return $null } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*subscribedSkus*') {
                    return @{ value = @(@{ capabilityStatus = 'Enabled'; servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }) }) }
                }
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate when WhatIf is specified' {
            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CAWhatIf') -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldCreate'
        }

        It 'Should not call batch operation when WhatIf is specified' {
            Mock Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit

            Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CAWhatIf') -WhatIf

            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 0
        }
    }

    Context 'Delete Mode' {
        BeforeAll {
            $caDir = Join-Path 'TestDrive:' 'CADelete'
            New-Item -Path $caDir -ItemType Directory -Force | Out-Null
            $caPolicy = @{
                displayName   = 'Block Legacy Auth'
                state         = 'disabled'
                conditions    = @{ applications = @{ includeApplications = @('All') } }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $caDir 'Block Legacy Auth.json') -Value $caPolicy

            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = (Join-Path 'TestDrive:' 'CADelete\Block Legacy Auth.json')
                        Name     = 'Block Legacy Auth.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-PremiumP2ServicePlans { return @('AAD_PREMIUM_P2') } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*subscribedSkus*') {
                    return @{ value = @(@{ capabilityStatus = 'Enabled'; servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }) }) }
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should delete disabled policies matching template names' {
            $script:caDeleteListCallCount = 0

            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                $script:caDeleteListCallCount++

                if ($ProcessItems) {
                    if ($script:caDeleteListCallCount -eq 1) {
                        & $ProcessItems @(
                            @{ id = 'ca-1'; displayName = '[IHD] Block Legacy Auth'; state = 'disabled' }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                return @([PSCustomObject]@{ Name = '[IHD] Block Legacy Auth'; Type = 'ConditionalAccessPolicy'; Action = 'Deleted'; Status = 'Success' })
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CADelete') -RemoveExisting -Confirm:$false

            $deleted = @($result | Where-Object { $_.Action -eq 'Deleted' })
            $deleted.Count | Should -Be 1
        }

        It 'Should skip enabled policies during delete' {
            $script:caListCallCount = 0

            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                $script:caListCallCount++

                if ($ProcessItems -and $script:caListCallCount -eq 1) {
                    & $ProcessItems @(
                        @{ id = 'ca-1'; displayName = '[IHD] Block Legacy Auth'; state = 'enabled' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CADelete') -RemoveExisting -Confirm:$false

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Skipped'
            $result[0].Status | Should -BeLike '*must be disabled*'
        }

        It 'Should return WouldDelete in WhatIf mode' {
            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'ca-1'; displayName = '[IHD] Block Legacy Auth'; state = 'disabled' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CADelete') -RemoveExisting -WhatIf

            $wouldDelete = @($result | Where-Object { $_.Action -eq 'WouldDelete' })
            $wouldDelete.Count | Should -Be 1
        }

        It 'Should refetch and delete newly visible disabled policies across delete passes' {
            $script:caListCallCount = 0
            $script:caTemplateFiles = @(
                [PSCustomObject]@{
                    FullName = (Join-Path 'TestDrive:' 'CADelete\Block Legacy Auth.json')
                    Name     = 'Block Legacy Auth.json'
                }
                [PSCustomObject]@{
                    FullName = (Join-Path 'TestDrive:' 'CADelete\Require MFA.json')
                    Name     = 'Require MFA.json'
                }
            )

            Mock Get-HydrationTemplates {
                $script:caTemplateFiles
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                $script:caListCallCount++

                if (-not $ProcessItems) {
                    return
                }

                switch ($script:caListCallCount) {
                    1 {
                        & $ProcessItems @(
                            @{ id = 'ca-1'; displayName = '[IHD] Block Legacy Auth'; state = 'disabled' }
                        )
                    }
                    2 {
                        & $ProcessItems @(
                            @{ id = 'ca-2'; displayName = '[IHD] Require MFA'; state = 'disabled' }
                        )
                    }
                    default { }
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                param($Items)
                foreach ($item in $Items) {
                    [PSCustomObject]@{
                        Name   = $item.Name
                        Type   = 'ConditionalAccessPolicy'
                        Action = 'Deleted'
                        Status = 'Success'
                    }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CADelete') -RemoveExisting -Confirm:$false

            $deleted = @($result | Where-Object { $_.Action -eq 'Deleted' })
            $deleted.Count | Should -Be 2
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 2
        }

        It 'Should not duplicate failed delete results across delete passes' {
            $script:caListCallCount = 0

            Mock Get-GraphPagedResults {
                param($Uri, $ProcessItems)
                $script:caListCallCount++

                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'ca-1'; displayName = '[IHD] Block Legacy Auth'; state = 'disabled' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-GraphBatchOperation {
                @([PSCustomObject]@{
                        Name   = '[IHD] Block Legacy Auth'
                        Type   = 'ConditionalAccessPolicy'
                        Action = 'Failed'
                        Status = 'Delete failed: Access denied'
                    })
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneConditionalAccessPolicy -TemplatePath (Join-Path 'TestDrive:' 'CADelete') -RemoveExisting -Confirm:$false

            $failed = @($result | Where-Object { $_.Action -eq 'Failed' })
            $failed.Count | Should -Be 1
            Should -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit -Times 1
        }
    }
}
