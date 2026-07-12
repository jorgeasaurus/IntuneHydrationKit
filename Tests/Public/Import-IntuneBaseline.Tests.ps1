#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    function New-TestFileSystemItem {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$FullName
        )

        [PSCustomObject]@{
            Name     = $Name
            FullName = $FullName
        }
    }
}

Describe 'Import-IntuneBaseline' {
    BeforeEach {
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Write-Progress -ModuleName IntuneHydrationKit
        Mock Start-Sleep -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { 'Test error message' } -ModuleName IntuneHydrationKit
        Mock Test-Path { $true } -ModuleName IntuneHydrationKit
    }

    Context 'Parameter validation' {
        It 'Should expose RepoUrl and Branch parameters' {
            $command = Get-Command Import-IntuneBaseline

            $command.Parameters['RepoUrl'] | Should -Not -BeNullOrEmpty
            $command.Parameters['Branch'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'IntuneManagement imports' {
        BeforeEach {
            $script:baselinePath = 'BaselineRoot'
            $script:windowsFolder = New-TestFileSystemItem -Name 'WINDOWS' -FullName 'BaselineRoot/WINDOWS'
            $script:intuneManagementFolder = New-TestFileSystemItem -Name 'IntuneManagement' -FullName 'BaselineRoot/WINDOWS/IntuneManagement'
            $script:settingsCatalogFile = New-TestFileSystemItem -Name 'SettingsCatalog.json' -FullName 'BaselineRoot/WINDOWS/IntuneManagement/SettingsCatalog.json'

            Mock Get-ChildItem {
                param($Path, $Filter, [switch]$Directory, [switch]$File, [switch]$Recurse)

                switch ($Path) {
                    $script:baselinePath { @($script:windowsFolder) }
                    $script:windowsFolder.FullName { @($script:intuneManagementFolder) }
                    $script:intuneManagementFolder.FullName { @($script:settingsCatalogFile) }
                    default { @() }
                }
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.deviceManagementConfigurationPolicy",
    "name": "Existing Settings Catalog Policy",
    "description": "Settings catalog export",
    "platforms": "windows10",
    "technologies": "mdm",
    "settings": []
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should detect duplicates by name when displayName is missing' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)

                if ($Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/configurationPolicies') {
                    return @{
                        value = @(
                            @{
                                id   = 'existing-policy-id'
                                name = 'Existing Settings Catalog Policy'
                            }
                        )
                    }
                }

                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }

                return @{ id = 'created-policy-id' }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath $script:baselinePath -TenantId 'tenant-id'

            @($result)[0].Action | Should -Be 'Skipped'
            @($result)[0].Status | Should -Be 'Already exists'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context 'App protection imports' {
        BeforeEach {
            $script:baselinePath = 'BaselineRoot'
            $script:byodFolder = New-TestFileSystemItem -Name 'BYOD' -FullName 'BaselineRoot/BYOD'
            $script:appProtectionFolder = New-TestFileSystemItem -Name 'AppProtection' -FullName 'BaselineRoot/BYOD/AppProtection'
            $script:appProtectionFile = New-TestFileSystemItem -Name 'Android-AppProtection.json' -FullName 'BaselineRoot/BYOD/AppProtection/Android-AppProtection.json'

            Mock Get-ChildItem {
                param($Path, $Filter, [switch]$Directory, [switch]$File, [switch]$Recurse)

                switch ($Path) {
                    $script:baselinePath { @($script:byodFolder) }
                    $script:byodFolder.FullName { @($script:appProtectionFolder) }
                    $script:appProtectionFolder.FullName { @($script:appProtectionFile) }
                    default { @() }
                }
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.androidManagedAppProtection",
    "displayName": "Android App Protection",
    "description": "Android BYOD app protection"
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should POST Android app protection policies to the concrete endpoint' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)

                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }

                return @{
                    id          = 'created-policy-id'
                    displayName = 'Android App Protection'
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneBaseline -BaselinePath $script:baselinePath -TenantId 'tenant-id'

            @($result)[0].Action | Should -Be 'Created'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'beta/deviceAppManagement/androidManagedAppProtections'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'beta/deviceAppManagement/managedAppPolicies'
            }
        }
    }
}
