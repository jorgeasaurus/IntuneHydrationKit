#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    # Get reference to the module
    $script:TestModule = Get-Module -Name IntuneHydrationKit | Select-Object -First 1

    if (-not $script:TestModule) {
        throw "Failed to import IntuneHydrationKit module"
    }
}

Describe 'New-IntuneDynamicGroup' {
    Context 'Parameter Validation' {
        It 'Should have mandatory DisplayName parameter' {
            $command = Get-Command New-IntuneDynamicGroup
            $param = $command.Parameters['DisplayName']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([string])
            ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have mandatory MembershipRule parameter' {
            $command = Get-Command New-IntuneDynamicGroup
            $param = $command.Parameters['MembershipRule']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([string])
            ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should support ShouldProcess (WhatIf)' {
            $command = Get-Command New-IntuneDynamicGroup
            $command.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }

        It 'Should validate MembershipRule starts with parenthesis' {
            $command = Get-Command New-IntuneDynamicGroup
            $validateScript = $command.Parameters['MembershipRule'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateScriptAttribute] }

            $validateScript | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When group already exists with prefixed name' {
        BeforeEach {
            Mock Get-GraphPagedResults {
                @(@{ id = 'existing-group-id'; displayName = '[IHD] Windows 11 Devices' })
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest { } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return Skipped result' {
            $result = New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Skipped'
        }

        It 'Should return existing group id' {
            $result = New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $result.Id | Should -Be 'existing-group-id'
        }

        It 'Should not call Invoke-MgGraphRequest' {
            New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ModuleName IntuneHydrationKit
        }
    }

    Context 'When group already exists with unprefixed legacy name' {
        BeforeEach {
            Mock Get-GraphPagedResults {
                @(@{ id = 'legacy-group-id'; displayName = 'Windows 11 Devices'; description = 'Imported by Intune Hydration Kit' })
            } -ModuleName IntuneHydrationKit

            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return Skipped result for backward compatibility' {
            $result = New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Skipped'
            $result.Id | Should -Be 'legacy-group-id'
        }
    }

    Context 'When group does not exist' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                @{ id = 'new-group-id'; displayName = '[IHD] Windows 11 Devices' }
            } -ModuleName IntuneHydrationKit

            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should create the group and return Created result' {
            $result = New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Created'
            $result.Id | Should -Be 'new-group-id'
        }

        It 'Should call Invoke-MgGraphRequest with POST method' {
            New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'beta/groups'
            }
        }

        It 'Should include [IHD] prefix in displayName' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Body)
                $script:capturedBody = $Body
                @{ id = 'new-group-id'; displayName = '[IHD] Windows 11 Devices' }
            } -ModuleName IntuneHydrationKit

            New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $script:capturedBody.displayName | Should -Be '[IHD] Windows 11 Devices'
        }

        It 'Should include dynamic membership groupTypes' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Body)
                $script:capturedBody = $Body
                @{ id = 'new-group-id'; displayName = '[IHD] Windows 11 Devices' }
            } -ModuleName IntuneHydrationKit

            New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $script:capturedBody.groupTypes | Should -Contain 'DynamicMembership'
        }

        It 'Should set membershipRule in request body' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Body)
                $script:capturedBody = $Body
                @{ id = 'new-group-id'; displayName = '[IHD] Windows 11 Devices' }
            } -ModuleName IntuneHydrationKit

            $rule = "(device.operatingSystem -eq 'Windows')"
            New-IntuneDynamicGroup -DisplayName 'Windows 11 Devices' -MembershipRule $rule

            $script:capturedBody.membershipRule | Should -Be $rule
        }
    }

    Context 'Description tagging' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should include hydration kit marker in description' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Body)
                $script:capturedBody = $Body
                @{ id = 'new-group-id'; displayName = '[IHD] Test Group' }
            } -ModuleName IntuneHydrationKit

            New-IntuneDynamicGroup -DisplayName 'Test Group' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $script:capturedBody.description | Should -BeLike '*Imported by Intune Hydration Kit*'
        }

        It 'Should preserve existing description text with marker appended' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Body)
                $script:capturedBody = $Body
                @{ id = 'new-group-id'; displayName = '[IHD] Test Group' }
            } -ModuleName IntuneHydrationKit

            New-IntuneDynamicGroup -DisplayName 'Test Group' -Description 'Custom description' -MembershipRule "(device.operatingSystem -eq 'Windows')"

            $script:capturedBody.description | Should -BeLike 'Custom description*Imported by Intune Hydration Kit*'
        }
    }

    Context 'WhatIf support' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit
            Mock Invoke-MgGraphRequest { } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate action without calling Graph API' {
            $result = New-IntuneDynamicGroup -DisplayName 'Test Group' -MembershipRule "(device.operatingSystem -eq 'Windows')" -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'WouldCreate'

            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ModuleName IntuneHydrationKit
        }
    }

    Context 'Error handling' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                throw "Graph API error: Forbidden"
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return Failed result when Graph API throws' {
            $result = New-IntuneDynamicGroup -DisplayName 'Failing Group' -MembershipRule "(device.operatingSystem -eq 'Windows')" -ErrorAction SilentlyContinue

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Failed'
        }

        It 'Should include error message in status' {
            $result = New-IntuneDynamicGroup -DisplayName 'Failing Group' -MembershipRule "(device.operatingSystem -eq 'Windows')" -ErrorAction SilentlyContinue

            $result.Status | Should -Not -BeNullOrEmpty
        }
    }
}
