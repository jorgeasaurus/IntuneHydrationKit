#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'Private' 'MobileApps' 'Test-IsWinGetTemplateFile.ps1'
    . $modulePath
}

Describe 'Test-IsWinGetTemplateFile' {
    It 'Should return true for a file under WinGet directory' {
        $testFile = [System.IO.FileInfo]::new('/Templates/MobileApps/Windows/WinGet/Apps/google-chrome.json')
        Test-IsWinGetTemplateFile -TemplateFile $testFile | Should -Be $true
    }

    It 'Should return true for a file nested under WinGet' {
        $testFile = [System.IO.FileInfo]::new('/Templates/MobileApps/Windows/WinGet/Presets/starter-pack.json')
        Test-IsWinGetTemplateFile -TemplateFile $testFile | Should -Be $true
    }

    It 'Should return false for a file not under WinGet' {
        $testFile = [System.IO.FileInfo]::new('/Templates/MobileApps/Windows/Store/CompanyPortal.json')
        Test-IsWinGetTemplateFile -TemplateFile $testFile | Should -Be $false
    }

    It 'Should return false for a macOS template file' {
        $testFile = [System.IO.FileInfo]::new('/Templates/MobileApps/macOS/MicrosoftRemoteDesktop.json')
        Test-IsWinGetTemplateFile -TemplateFile $testFile | Should -Be $false
    }
}
