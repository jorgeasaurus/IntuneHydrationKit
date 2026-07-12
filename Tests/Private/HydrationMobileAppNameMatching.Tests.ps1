#Requires -Modules Pester

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..' '..'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $moduleRoot 'IntuneHydrationKit.psd1') -Force
}

Describe 'Hydration mobile app name matching' {
    It 'Should find tagged existing apps by current suffix name' {
        InModuleScope IntuneHydrationKit {
            $existingApps = @{
                'Company Portal - [IHD]' = @{ Id = 'app-id'; IsTagged = $true }
            }

            Get-HydrationMobileAppExistingMatch -ExistingApps $existingApps -DisplayName 'Company Portal' |
                Should -Be 'Company Portal - [IHD]'
        }
    }

    It 'Should find tagged existing apps by legacy prefixed name' {
        InModuleScope IntuneHydrationKit {
            $existingApps = @{
                '[IHD] Company Portal' = @{ Id = 'app-id'; IsTagged = $true }
            }

            Get-HydrationMobileAppExistingMatch -ExistingApps $existingApps -DisplayName 'Company Portal' |
                Should -Be '[IHD] Company Portal'
        }
    }

    It 'Should ignore untagged existing apps' {
        InModuleScope IntuneHydrationKit {
            $existingApps = @{
                'Company Portal - [IHD]' = @{ Id = 'app-id'; IsTagged = $false }
            }

            Get-HydrationMobileAppExistingMatch -ExistingApps $existingApps -DisplayName 'Company Portal' |
                Should -BeNullOrEmpty
        }
    }

    It 'Should find owned WinGet apps using the ownership property selector' {
        InModuleScope IntuneHydrationKit {
            $existingApps = @{
                '[IHD] Company Portal' = [pscustomobject]@{ Id = 'app-id'; IsOwned = $true }
            }

            Get-HydrationMobileAppExistingMatch -ExistingApps $existingApps -DisplayName 'Company Portal' -OwnershipProperty IsOwned |
                Should -Be '[IHD] Company Portal'
        }
    }

    It 'Should fail closed when the selected ownership property is missing' {
        InModuleScope IntuneHydrationKit {
            $existingApps = @{
                'Company Portal - [IHD]' = [pscustomobject]@{ Id = 'app-id'; IsTagged = $true }
            }

            Get-HydrationMobileAppExistingMatch -ExistingApps $existingApps -DisplayName 'Company Portal' -OwnershipProperty IsOwned |
                Should -BeNullOrEmpty
        }
    }

    It 'Should match any supported name variant in a template name set' {
        InModuleScope IntuneHydrationKit {
            $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            [void]$nameSet.Add('Company Portal - [IHD]')

            Test-HydrationMobileAppNameInSet -DisplayName '[IHD] Company Portal' -NameSet $nameSet |
                Should -BeTrue
        }
    }
}
