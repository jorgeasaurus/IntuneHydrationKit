#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-HydrationGroupStep' {
    BeforeEach {
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
    }

    It 'Should exclude platform All dynamic group names from platform-scoped delete' {
        $templateDir = Join-Path 'TestDrive:' 'DynamicGroups'
        New-Item -Path $templateDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $templateDir 'Groups.json') -Value (@{
                groups = @(
                    @{ displayName = 'Windows Devices'; platform = 'Windows'; membershipRule = '(device.deviceOSType -eq "Windows")' }
                    @{ displayName = 'All Licensed Users'; platform = 'All'; membershipRule = '(user.assignedPlans -any true)' }
                )
            } | ConvertTo-Json -Depth 5)

        $script:capturedKnownNames = $null
        Mock Invoke-GroupBatchImport {
            param($KnownNames)
            $script:capturedKnownNames = $KnownNames
            return @()
        } -ModuleName IntuneHydrationKit

        InModuleScope IntuneHydrationKit -Parameters @{ TemplatePath = $templateDir } {
            Invoke-HydrationGroupStep `
                -StepLabel 'Step 3' `
                -GroupType 'Dynamic' `
                -TemplatePath $TemplatePath `
                -Platforms @('Windows') `
                -RemoveExisting $true `
                -WhatIfEnabled $false
        }

        $script:capturedKnownNames.Contains('Windows Devices') | Should -BeTrue
        $script:capturedKnownNames.Contains('All Licensed Users') | Should -BeFalse
    }

    It 'Should include platform All static group names only when deleting all platforms' {
        $templateDir = Join-Path 'TestDrive:' 'StaticGroups'
        New-Item -Path $templateDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $templateDir 'Groups.json') -Value (@{
                groups = @(
                    @{ displayName = 'Pilot Windows Devices'; platform = 'Windows' }
                    @{ displayName = 'Update Ring Pilot'; platform = 'All' }
                )
            } | ConvertTo-Json -Depth 5)

        $script:capturedKnownNames = $null
        Mock Invoke-GroupBatchImport {
            param($KnownNames)
            $script:capturedKnownNames = $KnownNames
            return @()
        } -ModuleName IntuneHydrationKit

        InModuleScope IntuneHydrationKit -Parameters @{ TemplatePath = $templateDir } {
            Invoke-HydrationGroupStep `
                -StepLabel 'Step 3b' `
                -GroupType 'Static' `
                -TemplatePath $TemplatePath `
                -Platforms @('All') `
                -RemoveExisting $true `
                -WhatIfEnabled $false
        }

        $script:capturedKnownNames.Contains('Pilot Windows Devices') | Should -BeTrue
        $script:capturedKnownNames.Contains('Update Ring Pilot') | Should -BeTrue
    }
}
