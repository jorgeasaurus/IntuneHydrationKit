#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\Get-ObfuscatedTenantId.ps1'
    . $functionPath
}

Describe 'Get-ObfuscatedTenantId' {
    Context 'GUID format' {
        It 'Should obfuscate GUID "<TenantValue>"' -TestCases @(
            @{ TenantValue = '12345678-1234-1234-1234-123456789abc'; Expected = '12345678****-****-****-123456789abc' }
            @{ TenantValue = 'abcdef01-2345-6789-abcd-ef0123456789'; Expected = 'abcdef01****-****-****-ef0123456789' }
            @{ TenantValue = '00000000-0000-0000-0000-000000000000'; Expected = '00000000****-****-****-000000000000' }
        ) {
            $result = Get-ObfuscatedTenantId -TenantId $TenantValue
            $result | Should -Be $Expected
        }
    }

    Context 'GUID format details' {
        It 'Should show first 8 characters of GUID' {
            $result = Get-ObfuscatedTenantId -TenantId '12345678-1234-1234-1234-123456789abc'
            $result | Should -BeLike '12345678*'
        }

        It 'Should show last 12 characters of GUID' {
            $result = Get-ObfuscatedTenantId -TenantId '12345678-1234-1234-1234-123456789abc'
            $result | Should -BeLike '*123456789abc'
        }

        It 'Should mask the middle sections' {
            $result = Get-ObfuscatedTenantId -TenantId '12345678-1234-1234-1234-123456789abc'
            $result | Should -Match '\*{4}-\*{4}-\*{4}-'
        }
    }

    Context 'Domain format' {
        It 'Should obfuscate domain "<TenantValue>"' -TestCases @(
            @{ TenantValue = 'contoso.onmicrosoft.com'; Expected = 'cont***' }
            @{ TenantValue = 'fabrikam.com'; Expected = 'fabr***' }
            @{ TenantValue = 'mycompany.onmicrosoft.com'; Expected = 'myco***' }
        ) {
            $result = Get-ObfuscatedTenantId -TenantId $TenantValue
            $result | Should -Be $Expected
        }
    }

    Context 'Short domain names' {
        It 'Should handle domain shorter than 4 characters gracefully' {
            $result = Get-ObfuscatedTenantId -TenantId 'ab'
            $result | Should -Be 'ab***'
        }

        It 'Should handle domain of exactly 4 characters' {
            $result = Get-ObfuscatedTenantId -TenantId 'test'
            $result | Should -Be 'test***'
        }

        It 'Should handle single character domain' {
            $result = Get-ObfuscatedTenantId -TenantId 'a'
            $result | Should -Be 'a***'
        }
    }

    Context 'Return type' {
        It 'Should return a string' {
            $result = Get-ObfuscatedTenantId -TenantId '12345678-1234-1234-1234-123456789abc'
            $result | Should -BeOfType [string]
        }
    }
}
