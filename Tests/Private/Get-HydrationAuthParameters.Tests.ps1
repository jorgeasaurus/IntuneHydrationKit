#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Auth/Get-HydrationAuthParameters.ps1
}

Describe 'Get-HydrationAuthParameters' {
    Context 'Interactive mode' {
        It 'Should return Interactive auth parameters without a client secret' {
            $result = Get-HydrationAuthParameters -AuthenticationSettings @{
                mode        = 'interactive'
                environment = 'USGov'
            } -TenantId '12345678-1234-1234-1234-123456789abc'

            $result.TenantId | Should -Be '12345678-1234-1234-1234-123456789abc'
            $result.Environment | Should -Be 'USGov'
            $result.Interactive | Should -Be $true
            $result.ContainsKey('ClientSecret') | Should -Be $false
        }

        It 'Should omit TenantId when interactive settings are tenantless' {
            $result = Get-HydrationAuthParameters -AuthenticationSettings @{
                mode        = 'interactive'
                environment = 'Global'
            }

            $result.ContainsKey('TenantId') | Should -BeFalse
            $result.Interactive | Should -Be $true
        }
    }

    Context 'Client secret mode' {
        It 'Should preserve SecureString secrets without converting them to plaintext first' {
            $secret = ConvertTo-SecureString 'super-secret' -AsPlainText -Force

            $result = Get-HydrationAuthParameters -AuthenticationSettings @{
                mode         = 'clientSecret'
                clientId     = 'app-id'
                clientSecret = $secret
                environment  = 'Global'
            } -TenantId '12345678-1234-1234-1234-123456789abc'

            $result.ClientId | Should -Be 'app-id'
            $result.ClientSecret | Should -BeOfType ([SecureString])
            ([pscredential]::new('user', $result.ClientSecret)).GetNetworkCredential().Password | Should -Be 'super-secret'
        }

        It 'Should still convert plaintext settings-file secrets to SecureString' {
            $result = Get-HydrationAuthParameters -AuthenticationSettings @{
                mode         = 'clientSecret'
                clientId     = 'app-id'
                clientSecret = 'settings-secret'
            } -TenantId '12345678-1234-1234-1234-123456789abc'

            $result.ClientSecret | Should -BeOfType ([SecureString])
            ([pscredential]::new('user', $result.ClientSecret)).GetNetworkCredential().Password | Should -Be 'settings-secret'
        }
    }
}
