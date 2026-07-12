#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'New-IntuneStaticGroup' {
    BeforeEach {
        Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
    }

    It 'Skips an existing static security group even when an incompatible same-named group is returned first' {
        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        id              = 'dynamic-id'
                        displayName     = 'Shared Name'
                        securityEnabled = $true
                        groupTypes      = @('DynamicMembership')
                    },
                    @{
                        id              = 'static-id'
                        displayName     = 'Shared Name'
                        securityEnabled = $true
                        groupTypes      = @()
                    }
                )
            }
        } -ModuleName IntuneHydrationKit

        $result = New-IntuneStaticGroup -DisplayName 'Shared Name'

        $result.Action | Should -Be 'Skipped'
        $result.Id | Should -Be 'static-id'
        Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'Fails when only a non-static security same-named group exists' {
        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        id              = 'dynamic-id'
                        displayName     = 'Shared Name'
                        securityEnabled = $true
                        groupTypes      = @('DynamicMembership')
                    }
                )
            }
        } -ModuleName IntuneHydrationKit

        $result = New-IntuneStaticGroup -DisplayName 'Shared Name' -WarningAction SilentlyContinue

        $result.Action | Should -Be 'Failed'
        $result.Status | Should -Be 'A non-static security group with this displayName already exists'
        Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
    }
}
