#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Format-WinGetInstallerSummary.ps1
    . $PSScriptRoot/../../Private/WinGet/Get-IntuneWinPackagingCapability.ps1
    . $PSScriptRoot/../../Private/WinGet/New-IntuneWinPackagingContext.ps1
    . $PSScriptRoot/../../Private/WinGet/New-IntuneWinPackage.ps1
    . $PSScriptRoot/../../Private/WinGet/Get-IntuneWinPackageMetadata.ps1
    . $PSScriptRoot/../../Private/WinGet/Expand-IntuneWinPackageEncryptedContent.ps1
}

Describe 'New-IntuneWinPackage' {
    BeforeEach {
        $script:artifactRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/New-IntuneWinPackage'
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }

        $null = New-Item -Path $script:artifactRoot -ItemType Directory -Force
        $script:sourceRoot = Join-Path $script:artifactRoot 'source'
        $null = New-Item -Path $script:sourceRoot -ItemType Directory -Force
        Set-Content -Path (Join-Path $script:sourceRoot 'Install-WinGetPackage.ps1') -Value "Write-Output 'install'"
        Set-Content -Path (Join-Path $script:sourceRoot 'support.txt') -Value 'wrapper-data'
        $script:outputPath = Join-Path $script:artifactRoot 'contoso.intunewin'
        $script:packageMetadata = [pscustomobject]@{
            PackageIdentifier = 'Contoso.App'
            PackageVersion    = '1.0.0'
            DisplayName       = 'Contoso App'
            Publisher         = 'Contoso'
            SelectedInstaller = [pscustomobject]@{
                InstallerUrl = 'https://downloads.contoso.test/app.exe'
            }
        }
    }

    AfterEach {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
    }

    It 'Should generate a portal-compatible intunewin package' {
        $context = New-IntuneWinPackagingContext -PackageMetadata $script:packageMetadata -SourcePath $script:sourceRoot -SetupFile 'Install-WinGetPackage.ps1' -OutputPath $script:outputPath

        $result = New-IntuneWinPackage -PackagingContext $context
        $metadata = Get-IntuneWinPackageMetadata -IntuneWinPath $script:outputPath

        $result.OutputPath | Should -Be $script:outputPath
        $metadata.FileName | Should -Be 'IntunePackage.intunewin'
        $metadata.SetupFile | Should -Be 'Install-WinGetPackage.ps1'
        $metadata.UnencryptedSize | Should -BeGreaterThan 0
        $metadata.FileDigestAlgorithm | Should -Be 'SHA256'
    }

    It 'Should include the encrypted payload in the package' {
        $context = New-IntuneWinPackagingContext -PackageMetadata $script:packageMetadata -SourcePath $script:sourceRoot -SetupFile 'Install-WinGetPackage.ps1' -OutputPath $script:outputPath
        $null = New-IntuneWinPackage -PackagingContext $context

        $extractedPath = Join-Path $script:artifactRoot 'IntunePackage.bin'
        $result = Expand-IntuneWinPackageEncryptedContent -IntuneWinPath $script:outputPath -FileName 'IntunePackage.intunewin' -DestinationPath $extractedPath

        $result | Should -Not -BeNullOrEmpty
        $result.Length | Should -BeGreaterThan 0
    }
}
