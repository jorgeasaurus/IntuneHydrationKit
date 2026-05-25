#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'Private' 'Configuration' 'Test-PlatformSelected.ps1'
    . $modulePath
}

Describe 'Test-PlatformSelected' {
    It 'Should return true when platform is in SelectedPlatforms' {
        Test-PlatformSelected -SelectedPlatforms @('Windows', 'macOS') -PlatformName 'Windows' | Should -Be $true
    }

    It 'Should return true when All is in SelectedPlatforms' {
        Test-PlatformSelected -SelectedPlatforms @('All') -PlatformName 'Linux' | Should -Be $true
    }

    It 'Should return false when platform is not in SelectedPlatforms' {
        Test-PlatformSelected -SelectedPlatforms @('Windows') -PlatformName 'macOS' | Should -Be $false
    }

    It 'Should return false when SelectedPlatforms is empty' {
        Test-PlatformSelected -SelectedPlatforms @() -PlatformName 'Windows' | Should -Be $false
    }
}
