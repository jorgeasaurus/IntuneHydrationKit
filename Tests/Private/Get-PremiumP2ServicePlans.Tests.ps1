#Requires -Modules Pester

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Private\Get-PremiumP2ServicePlans.ps1')
}

Describe 'Get-PremiumP2ServicePlans' {
    It 'Does not include Defender-only plans that do not grant Entra ID P2' {
        $plans = Get-PremiumP2ServicePlans

        $plans | Should -Not -Contain 'ADALLOM_S_STANDALONE'
        $plans | Should -Not -Contain 'ATA'
    }

    It 'Keeps known Entra ID P2-capable plans' {
        $plans = Get-PremiumP2ServicePlans

        $plans | Should -Contain 'AAD_PREMIUM_P2'
        $plans | Should -Contain 'SPE_E5'
        $plans | Should -Contain 'IDENTITY_THREAT_PROTECTION'
    }
}
