#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
    $script:TestModule = Get-Module -Name IntuneHydrationKit | Select-Object -First 1
}

Describe 'Get-IntuneProactiveRemediationAvailability' {
    It 'Should return Available when the Graph probe succeeds' {
        Mock Invoke-HydrationGraphRequest { @{ value = @() } } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            Get-IntuneProactiveRemediationAvailability
        }

        $result.IsAvailable | Should -BeTrue
        $result.Status | Should -Be 'Available'
    }

    It 'Should return FeatureUnavailable for tenant capability failures' {
        Mock Invoke-HydrationGraphRequest { throw 'probe failed' } -ModuleName IntuneHydrationKit
        Mock Get-GraphStatusCode { 404 } -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { 'HTTP 404 - Resource not found' } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            Get-IntuneProactiveRemediationAvailability
        }

        $result.IsAvailable | Should -BeFalse
        $result.Status | Should -Be 'FeatureUnavailable'
    }

    It 'Should return InsufficientPermissions for permission failures' {
        Mock Invoke-HydrationGraphRequest { throw 'probe failed' } -ModuleName IntuneHydrationKit
        Mock Get-GraphStatusCode { 403 } -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { 'HTTP 403 - Access denied - check permissions' } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            Get-IntuneProactiveRemediationAvailability
        }

        $result.IsAvailable | Should -BeFalse
        $result.Status | Should -Be 'InsufficientPermissions'
    }
}
