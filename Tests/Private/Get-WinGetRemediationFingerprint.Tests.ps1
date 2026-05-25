#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-WinGetRemediationFingerprint.ps1
}

Describe 'Get-WinGetRemediationFingerprint' {
    It 'Should produce a stable 16-character fingerprint from sorted unique package identifiers' {
        $result = Get-WinGetRemediationFingerprint -PackageIdentifiers @(
            'Contoso.User',
            'Contoso.Machine',
            'Contoso.User',
            ' '
        )

        $result | Should -Be '9154625C4EF3E6D6'
    }

    It 'Should use PowerShell 7.0 compatible SHA256 APIs' {
        $source = Get-Content -Path "$PSScriptRoot/../../Private/WinGet/Get-WinGetRemediationFingerprint.ps1" -Raw

        $source | Should -Match 'ComputeHash'
        $source | Should -Not -Match 'HashData'
    }
}
