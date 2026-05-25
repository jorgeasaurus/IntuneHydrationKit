#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Hydration/Deduplicate-HydrationDeleteCandidates.ps1
}

Describe 'Deduplicate-HydrationDeleteCandidates' {
    It 'Should return a flat array of unique candidates' {
        $result = Deduplicate-HydrationDeleteCandidates -Candidates @(
            @{ Name = 'Policy A'; Id = '1'; Url = '/one' }
            @{ Name = 'Policy A'; Id = '2'; Url = '/two' }
            @{ Name = 'Policy B'; Id = '3'; Url = '/three' }
        )

        $result | Should -HaveCount 2
        $result[0] | Should -BeOfType ([hashtable])
        $result.Name | Should -Be @('Policy A', 'Policy B')
        $result.Id | Should -Be @('1', '3')
    }

    It 'Should treat names as case-insensitive duplicates' {
        $result = @(Deduplicate-HydrationDeleteCandidates -Candidates @(
            @{ Name = 'Policy A'; Id = '1'; Url = '/one' }
            @{ Name = 'policy a'; Id = '2'; Url = '/two' }
        ))

        $result | Should -HaveCount 1
        $result[0].Name | Should -Be 'Policy A'
        $result[0].Id | Should -Be '1'
    }
}
