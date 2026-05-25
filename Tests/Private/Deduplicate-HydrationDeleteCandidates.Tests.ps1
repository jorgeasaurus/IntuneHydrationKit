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
        $result.Name | Should -Contain 'Policy A'
        $result.Name | Should -Contain 'Policy B'
    }
}
