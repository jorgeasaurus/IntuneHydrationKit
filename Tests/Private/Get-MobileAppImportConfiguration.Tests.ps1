#Requires -Modules Pester

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '..' 'Private' 'Utilities' 'Get-ConfigurationSection.ps1')
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'Private' 'MobileApps' 'Get-MobileAppImportConfiguration.ps1'
    . $modulePath
}

Describe 'Get-MobileAppImportConfiguration' {
    It 'Should return defaults when mobileApps section is absent' {
        $settings = @{}
        $result = Get-MobileAppImportConfiguration -Settings $settings

        $result.presetId | Should -Be $null
        $result.templateIds | Should -BeNullOrEmpty
        $result.remediationEnabled | Should -Be $true
    }

    It 'Should return defaults when mobileApps section is null' {
        $settings = @{ mobileApps = $null }
        $result = Get-MobileAppImportConfiguration -Settings $settings

        $result.presetId | Should -Be $null
        $result.templateIds | Should -BeNullOrEmpty
        $result.remediationEnabled | Should -Be $true
    }

    It 'Should extract presetId and templateIds' {
        $settings = @{
            mobileApps = @{
                presetId    = 'starter-pack'
                templateIds = @('google-chrome', 'vscode')
                remediation = @{ enabled = $true }
            }
        }
        $result = Get-MobileAppImportConfiguration -Settings $settings

        $result.presetId | Should -Be 'starter-pack'
        $result.templateIds | Should -Be @('google-chrome', 'vscode')
        $result.remediationEnabled | Should -Be $true
    }

    It 'Should drop blank template IDs and presetId' {
        $settings = @{
            mobileApps = @{
                presetId    = ' '
                templateIds = @('', '   ', $null, 'valid-app')
            }
        }
        $result = Get-MobileAppImportConfiguration -Settings $settings

        $result.presetId | Should -Be $null
        $result.templateIds | Should -Be @('valid-app')
    }

    It 'Should parse remediation enabled false' {
        $settings = @{
            mobileApps = @{
                remediation = @{ enabled = $false }
            }
        }
        $result = Get-MobileAppImportConfiguration -Settings $settings

        $result.remediationEnabled | Should -Be $false
    }

    It 'Should keep remediation enabled when remediation section omits enabled' {
        $settings = @{
            mobileApps = @{
                remediation = @{}
            }
        }
        $result = Get-MobileAppImportConfiguration -Settings $settings

        $result.remediationEnabled | Should -Be $true
    }

    It 'Should keep remediation enabled when remediation enabled is null' {
        $settings = @{
            mobileApps = @{
                remediation = @{ enabled = $null }
            }
        }
        $result = Get-MobileAppImportConfiguration -Settings $settings

        $result.remediationEnabled | Should -Be $true
    }
}
