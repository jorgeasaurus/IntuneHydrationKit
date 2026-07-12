#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Auth\Get-PremiumP2ServicePlans.ps1'
    . $functionPath
}

Describe 'Get-PremiumP2ServicePlans' {
    Context 'Return value' {
        BeforeAll {
            $script:plans = Get-PremiumP2ServicePlans
        }

        It 'Should return a non-empty array' {
            $script:plans | Should -Not -BeNullOrEmpty
            $script:plans.Count | Should -BeGreaterThan 0
        }

        It 'Should return string elements' {
            $script:plans | Should -HaveCount $script:plans.Count
            $script:plans[0] | Should -BeOfType [string]
        }
    }

    Context 'Expected P2 plans are present' -ForEach @(
        @{ Plan = 'AAD_PREMIUM_P2' }
        @{ Plan = 'SPE_E5' }
        @{ Plan = 'EMSPREMIUM' }
        @{ Plan = 'M365EDU_A5_FACULTY' }
        @{ Plan = 'IDENTITY_THREAT_PROTECTION' }
        @{ Plan = 'ATA' }
    ) {
        It 'Should contain <Plan>' {
            $result = Get-PremiumP2ServicePlans
            $result | Should -Contain $Plan
        }
    }

    Context 'Non-P2 plans are excluded' -ForEach @(
        @{ Plan = 'INTUNE_A' }
        @{ Plan = 'AAD_PREMIUM' }
        @{ Plan = 'SPE_E3' }
        @{ Plan = 'EXCHANGESTANDARD' }
    ) {
        It 'Should NOT contain <Plan>' {
            $result = Get-PremiumP2ServicePlans
            $result | Should -Not -Contain $Plan
        }
    }

    Context 'Consistency' {
        It 'Should return the same plans on repeated calls' {
            $first = Get-PremiumP2ServicePlans
            $second = Get-PremiumP2ServicePlans
            $first | Should -Be $second
        }
    }
}
