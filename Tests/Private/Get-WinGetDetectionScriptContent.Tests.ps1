#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-WinGetBootstrapScriptFragment.ps1
    . $PSScriptRoot/../../Private/WinGet/Get-WinGetDetectionScriptContent.ps1
}

Describe 'Get-WinGetDetectionScriptContent' {
    It 'Should generate WinGet detection with exact ID matching and uninstall registry fallback' {
        $scriptContent = Get-WinGetDetectionScriptContent -PackageIdentifier 'Adobe.Acrobat.Reader.64-bit' -DisplayName 'Adobe Acrobat Reader DC' -Publisher 'ADOBE INC.'

        $scriptContent | Should -Match ([regex]::Escape('$PackageIdentifier = ''Adobe.Acrobat.Reader.64-bit'''))
        $scriptContent | Should -Match ([regex]::Escape('$DisplayName = ''Adobe Acrobat Reader DC'''))
        $scriptContent | Should -Match ([regex]::Escape('$Publisher = ''ADOBE INC.'''))
        $scriptContent | Should -Match ([regex]::Escape('winget list --id "$PackageIdentifier" --exact --accept-source-agreements'))
        $scriptContent | Should -Not -Match ([regex]::Escape('--source winget'))
        $scriptContent | Should -Match 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\*'
        $scriptContent | Should -Match 'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\*'
        $scriptContent | Should -Match 'Test-InstalledApplicationRegistry'

        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
    }
}
