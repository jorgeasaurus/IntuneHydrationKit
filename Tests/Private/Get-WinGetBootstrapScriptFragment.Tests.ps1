#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-WinGetBootstrapScriptFragment.ps1
}

Describe 'Get-WinGetBootstrapScriptFragment' {
    It 'Should generate a reusable ZipFile-based WinGet bootstrap fragment' {
        $result = Get-WinGetBootstrapScriptFragment -LogFunctionName 'Write-TestLog' -BootstrapMessage 'Bootstrapping WinGet for tests.'

        $result | Should -Match 'function Get-WinGetExecutablePath'
        $result | Should -Match 'function Install-WinGetSystemBootstrap'
        $result | Should -Match 'System\.IO\.Compression\.ZipFile'
        $result | Should -Match "Write-TestLog -Message 'Bootstrapping WinGet for tests\.'"
        $result | Should -Not -Match '7zip|7za|Install-WingetWith7Zip'
    }
}
