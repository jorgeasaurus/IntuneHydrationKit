#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-IntuneWinPackageMetadata.ps1
}

Describe 'Get-IntuneWinPackageMetadata' {
    BeforeAll {
        $script:artifactRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/Get-IntuneWinPackageMetadata'
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }

        $null = New-Item -Path $script:artifactRoot -ItemType Directory -Force
        $packageRoot = Join-Path $script:artifactRoot 'source'
        $metadataRoot = Join-Path $packageRoot 'Metadata'
        $contentsRoot = Join-Path $packageRoot 'Contents'
        $null = New-Item -Path $metadataRoot -ItemType Directory -Force
        $null = New-Item -Path $contentsRoot -ItemType Directory -Force

        @'
<ApplicationInfo>
  <FileName>app.bin</FileName>
  <SetupFile>setup.exe</SetupFile>
  <UnencryptedContentSize>12345</UnencryptedContentSize>
  <EncryptionInfo>
    <EncryptionKey>enc-key</EncryptionKey>
    <MacKey>mac-key</MacKey>
    <InitializationVector>iv</InitializationVector>
    <Mac>mac</Mac>
    <ProfileIdentifier>profile</ProfileIdentifier>
    <FileDigest>digest</FileDigest>
    <FileDigestAlgorithm>SHA256</FileDigestAlgorithm>
  </EncryptionInfo>
</ApplicationInfo>
'@ | Set-Content -Path (Join-Path $metadataRoot 'Detection.xml')
        'encrypted-content' | Set-Content -Path (Join-Path $contentsRoot 'app.bin')

        $script:packagePath = Join-Path $script:artifactRoot 'sample.intunewin'
        Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $script:packagePath -Force
    }

    AfterAll {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
    }

    It 'Should parse Detection.xml metadata from the package' {
        $result = Get-IntuneWinPackageMetadata -IntuneWinPath $script:packagePath

        $result.FileName | Should -Be 'app.bin'
        $result.SetupFile | Should -Be 'setup.exe'
        $result.UnencryptedSize | Should -Be 12345
        $result.FileDigestAlgorithm | Should -Be 'SHA256'
    }

    It 'Should throw when Detection.xml is missing' {
        $emptyRoot = Join-Path $script:artifactRoot 'missing-detection'
        $null = New-Item -Path $emptyRoot -ItemType Directory -Force
        'content' | Set-Content -Path (Join-Path $emptyRoot 'app.bin')
        $missingDetectionPath = Join-Path $script:artifactRoot 'missing.intunewin'
        Compress-Archive -Path (Join-Path $emptyRoot '*') -DestinationPath $missingDetectionPath -Force

        { Get-IntuneWinPackageMetadata -IntuneWinPath $missingDetectionPath } | Should -Throw '*Detection.xml*'
    }
}
