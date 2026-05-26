#Requires -Modules Pester

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..' '..'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $moduleRoot 'IntuneHydrationKit.psd1') -Force
}

Describe 'Get-HydrationMobileAppBaseName' {
    It 'Should normalize raw, legacy-prefixed, and current suffixed names to the same base name' {
        InModuleScope IntuneHydrationKit {
            Get-HydrationMobileAppBaseName -DisplayName 'Company Portal' |
                Should -Be 'Company Portal'
            Get-HydrationMobileAppBaseName -DisplayName '[IHD] Company Portal' |
                Should -Be 'Company Portal'
            Get-HydrationMobileAppBaseName -DisplayName 'Company Portal - [IHD]' |
                Should -Be 'Company Portal'
        }
    }
}

Describe 'Get-HydrationMobileAppDisplayName' {
    It 'Should append the app-name-first suffix to raw template names' {
        InModuleScope IntuneHydrationKit {
            Get-HydrationMobileAppDisplayName -DisplayName 'Company Portal' |
                Should -Be 'Company Portal - [IHD]'
        }
    }

    It 'Should normalize legacy-prefixed template names to the app-name-first suffix' {
        InModuleScope IntuneHydrationKit {
            Get-HydrationMobileAppDisplayName -DisplayName '[IHD] Company Portal' |
                Should -Be 'Company Portal - [IHD]'
        }
    }

    It 'Should not duplicate the app-name-first suffix' {
        InModuleScope IntuneHydrationKit {
            Get-HydrationMobileAppDisplayName -DisplayName 'Company Portal - [IHD]' |
                Should -Be 'Company Portal - [IHD]'
        }
    }
}

Describe 'Get-HydrationMobileAppNameVariant' {
    It 'Should return current, raw, and legacy-prefixed variants for template names' {
        InModuleScope IntuneHydrationKit {
            $result = Get-HydrationMobileAppNameVariant -DisplayName 'Company Portal'

            $result | Should -Contain 'Company Portal - [IHD]'
            $result | Should -Contain 'Company Portal'
            $result | Should -Contain '[IHD] Company Portal'
        }
    }

    It 'Should normalize legacy-prefixed app names back to the raw template name' {
        InModuleScope IntuneHydrationKit {
            $result = Get-HydrationMobileAppNameVariant -DisplayName '[IHD] Company Portal'

            $result | Should -Contain 'Company Portal'
            $result | Should -Contain '[IHD] Company Portal'
            $result | Should -Contain 'Company Portal - [IHD]'
            $result | Should -Not -Contain '[IHD] Company Portal - [IHD]'
        }
    }

    It 'Should normalize current suffixed app names back to the raw template name' {
        InModuleScope IntuneHydrationKit {
            $result = Get-HydrationMobileAppNameVariant -DisplayName 'Company Portal - [IHD]'

            $result | Should -Contain 'Company Portal'
            $result | Should -Contain 'Company Portal - [IHD]'
        }
    }
}
