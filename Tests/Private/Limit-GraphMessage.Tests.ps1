#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Graph/Limit-GraphMessage.ps1
}

Describe 'Limit-GraphMessage' {
    It 'Should return empty string for null input' {
        Limit-GraphMessage -Message $null -MaximumLength 100 | Should -Be ''
    }

    It 'Should truncate messages longer than the maximum length' {
        Limit-GraphMessage -Message ('A' * 12) -MaximumLength 5 | Should -Be 'AAAAA...'
    }

    It 'Should reject non-positive maximum lengths' {
        { Limit-GraphMessage -Message 'Graph error' -MaximumLength 0 } | Should -Throw
    }
}
