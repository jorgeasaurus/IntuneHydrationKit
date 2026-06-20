#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-WinGetBootstrapScriptFragment.ps1
    . $PSScriptRoot/../../Private/WinGet/Get-WinGetWrapperScriptContent.ps1
}

Describe 'Get-WinGetBootstrapScriptFragment' {
    It 'Should generate a reusable ZipFile-based WinGet bootstrap fragment' {
        $result = Get-WinGetBootstrapScriptFragment -LogFunctionName 'Write-TestLog' -BootstrapMessage 'Bootstrapping WinGet for tests.'

        $result | Should -Match 'function Get-WinGetExecutablePath'
        $result | Should -Match 'function Get-UserWinGetExecutablePath'
        $result | Should -Match 'function Install-WinGetSystemBootstrap'
        $result | Should -Match 'System\.IO\.Compression\.ZipFile'
        $result | Should -Match "Write-TestLog -Message 'Bootstrapping WinGet for tests\.'"
        $result.Contains('$programDataRoot = if ([string]::IsNullOrWhiteSpace($env:ProgramData)) { ''C:\ProgramData'' } else { $env:ProgramData }') | Should -BeTrue
        $result.Contains('$programDataWingetRoot = Join-Path -Path $programDataRoot -ChildPath ''Microsoft.DesktopAppInstaller''') | Should -BeTrue
        $result.Contains('$tempRoot = [System.IO.Path]::GetTempPath()') | Should -BeTrue
        $result.Contains('$tempRoot = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { ''C:\Windows\Temp'' } else { $env:TEMP }') | Should -BeTrue
        $result.Contains('$stagingRoot = Join-Path -Path $tempRoot -ChildPath ''IntuneHydrationKit-WinGetBootstrap''') | Should -BeTrue
        $result | Should -Match 'if \(-not \$isSystem\)'
        $result | Should -Match '\[string\]::IsNullOrWhiteSpace\(\$env:LOCALAPPDATA\)'
        $result | Should -Match '\[string\]::IsNullOrWhiteSpace\(\$env:ProgramFiles\)'
        $result | Should -Match '\[string\]::IsNullOrWhiteSpace\(\$\{env:ProgramFiles\(x86\)\}\)'
        $result | Should -Match 'winget\.exe could not be located for this user context'
        $result | Should -Not -Match '7zip|7za|Install-WingetWith7Zip'
    }

    It 'Should generate a parseable log directory fallback helper' {
        $result = Get-WinGetLogDirectoryScriptFragment

        $result | Should -Match 'function Test-HydrationWinGetLogDirectory'
        $result | Should -Match 'function Get-HydrationWinGetLogDirectory'
        $result | Should -Match 'Microsoft\\IntuneManagementExtension\\Logs'
        $result | Should -Match 'IntuneHydrationKit\\Logs'
        $result | Should -Match 'IntuneHydrationKit-LogProbe'
        $result | Should -Match 'No writable log directory was available'

        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($result, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
    }
}
