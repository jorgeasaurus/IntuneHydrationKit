#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Format-WinGetInstallerSummary.ps1
    . $PSScriptRoot/../../Private/WinGet/Get-IntuneWinPackagingCapability.ps1
    . $PSScriptRoot/../../Private/WinGet/New-IntuneWinPackagingContext.ps1
}

Describe 'New-IntuneWinPackagingContext' {
    It 'Should infer setup file from selected installer metadata' {
        $packageMetadata = [PSCustomObject]@{
            PackageIdentifier = 'Contoso.App'
            PackageVersion    = '2.0.0'
            DisplayName       = 'Contoso App'
            Publisher         = 'Contoso'
            ManifestSource    = [PSCustomObject]@{
                Type = 'GitHub'
            }
            SelectedInstaller = [PSCustomObject]@{
                InstallerUrl = 'https://downloads.contoso.test/app-machine.exe'
            }
        }

        $result = New-IntuneWinPackagingContext -PackageMetadata $packageMetadata -SourcePath 'TestDrive:/staging'

        $result.PackageFormat | Should -Be 'intunewin'
        $result.Source | Should -Be 'WinGet'
        $result.PackageIdentifier | Should -Be 'Contoso.App'
        $result.SetupFile | Should -Be 'app-machine.exe'
        $result.PackagingCapability | Should -Not -BeNullOrEmpty
        $result.PackagingCapability.Capabilities.ZipArchive | Should -BeTrue
    }
}
