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
        $scriptContent | Should -Match ([regex]::Escape('Write-Output "$PackageIdentifier is installed"'))
        $scriptContent | Should -Match ([regex]::Escape('Write-Output "$PackageIdentifier is not installed"'))
        $scriptContent | Should -Not -Match 'Write-Host'

        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
    }

    It 'Should keep bootstrap log messages out of the success stream' {
        $scriptContent = Get-WinGetDetectionScriptContent -PackageIdentifier 'Contoso.App'
        $loggerDefinition = [regex]::Match($scriptContent, '(?ms)^function Write-WinGetDetectionLog \{.*?^\}')

        $loggerDefinition.Success | Should -BeTrue
        . ([scriptblock]::Create($loggerDefinition.Value))

        $successOutput = @(Write-WinGetDetectionLog -Message 'Bootstrapping WinGet for detection.')

        $successOutput | Should -BeNullOrEmpty
    }
}
