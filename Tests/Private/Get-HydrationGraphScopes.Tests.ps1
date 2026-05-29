#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Get-HydrationGraphScopes' {
    It 'Should keep the full scope set when no import selection is provided' {
        InModuleScope IntuneHydrationKit {
            $scopes = Get-HydrationGraphScopes

            $scopes | Should -Contain 'DeviceManagementManagedDevices.ReadWrite.All'
            $scopes | Should -Contain 'Group.ReadWrite.All'
            $scopes | Should -Contain 'Policy.ReadWrite.ConditionalAccess'
            $scopes | Should -Contain 'Organization.Read.All'
            $scopes | Should -Contain 'LicenseAssignment.Read.All'
        }
    }

    It 'Should request only base and selected workload scopes for device filters' {
        InModuleScope IntuneHydrationKit {
            $scopes = Get-HydrationGraphScopes -Imports @{
                deviceFilters     = $true
                dynamicGroups     = $false
                conditionalAccess = $false
            } -Create

            $scopes | Should -Contain 'Organization.Read.All'
            $scopes | Should -Contain 'LicenseAssignment.Read.All'
            $scopes | Should -Contain 'DeviceManagementConfiguration.ReadWrite.All'
            $scopes | Should -Not -Contain 'Group.ReadWrite.All'
            $scopes | Should -Not -Contain 'Policy.ReadWrite.ConditionalAccess'
            $scopes | Should -Not -Contain 'DeviceManagementApps.ReadWrite.All'
        }
    }

    It 'Should include static group owner scopes for create but not delete-only runs' {
        InModuleScope IntuneHydrationKit {
            $createScopes = Get-HydrationGraphScopes -Imports @{ staticGroups = $true } -Create
            $deleteScopes = Get-HydrationGraphScopes -Imports @{ staticGroups = $true } -Delete

            $createScopes | Should -Contain 'Group.ReadWrite.All'
            $createScopes | Should -Contain 'Application.Read.All'
            $createScopes | Should -Contain 'Directory.ReadWrite.All'

            $deleteScopes | Should -Contain 'Group.ReadWrite.All'
            $deleteScopes | Should -Not -Contain 'Application.Read.All'
            $deleteScopes | Should -Not -Contain 'Directory.ReadWrite.All'
        }
    }

    It 'Should include WinGet remediation script scope only when selected mobile apps can use remediation' {
        InModuleScope IntuneHydrationKit {
            $defaultScopes = Get-HydrationGraphScopes -Imports @{ mobileApps = $true } -Create -MobileAppPlatforms @('Windows')
            $disabledScopes = Get-HydrationGraphScopes `
                -Imports @{ mobileApps = $true } `
                -Create `
                -MobileAppConfiguration @{ remediationEnabled = $false } `
                -MobileAppPlatforms @('Windows')
            $macScopes = Get-HydrationGraphScopes -Imports @{ mobileApps = $true } -Create -MobileAppPlatforms @('macOS')

            $defaultScopes | Should -Contain 'DeviceManagementApps.ReadWrite.All'
            $defaultScopes | Should -Contain 'DeviceManagementScripts.ReadWrite.All'
            $disabledScopes | Should -Contain 'DeviceManagementApps.ReadWrite.All'
            $disabledScopes | Should -Not -Contain 'DeviceManagementScripts.ReadWrite.All'
            $macScopes | Should -Contain 'DeviceManagementApps.ReadWrite.All'
            $macScopes | Should -Not -Contain 'DeviceManagementScripts.ReadWrite.All'
        }
    }
}
