#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Get-ResultSummary.ps1'
    . $functionPath
}

Describe 'Get-ResultSummary' {
    Context 'Empty results' {
        It 'Should return all zeros for empty array' {
            $result = Get-ResultSummary -Results @()
            $result.Created | Should -Be 0
            $result.Updated | Should -Be 0
            $result.Deleted | Should -Be 0
            $result.Skipped | Should -Be 0
            $result.WouldCreate | Should -Be 0
            $result.WouldUpdate | Should -Be 0
            $result.WouldDelete | Should -Be 0
            $result.Failed | Should -Be 0
        }

        It 'Should return all zeros when called without parameters' {
            $result = Get-ResultSummary
            $result.Created | Should -Be 0
            $result.Failed | Should -Be 0
        }
    }

    Context 'Mixed results' {
        BeforeAll {
            $results = @(
                [PSCustomObject]@{ Action = 'Created' }
                [PSCustomObject]@{ Action = 'Created' }
                [PSCustomObject]@{ Action = 'Updated' }
                [PSCustomObject]@{ Action = 'Deleted' }
                [PSCustomObject]@{ Action = 'Skipped' }
                [PSCustomObject]@{ Action = 'Skipped' }
                [PSCustomObject]@{ Action = 'Skipped' }
                [PSCustomObject]@{ Action = 'Failed' }
                [PSCustomObject]@{ Action = 'WouldCreate' }
                [PSCustomObject]@{ Action = 'WouldDelete' }
            )
            $script:summary = Get-ResultSummary -Results $results
        }

        It 'Should count Created correctly' {
            $script:summary.Created | Should -Be 2
        }

        It 'Should count Updated correctly' {
            $script:summary.Updated | Should -Be 1
        }

        It 'Should count Deleted correctly' {
            $script:summary.Deleted | Should -Be 1
        }

        It 'Should count Skipped correctly' {
            $script:summary.Skipped | Should -Be 3
        }

        It 'Should count WouldCreate correctly' {
            $summary.WouldCreate | Should -Be 1
        }

        It 'Should count WouldDelete correctly' {
            $summary.WouldDelete | Should -Be 1
        }

        It 'Should count Failed correctly' {
            $summary.Failed | Should -Be 1
        }

        It 'Should count WouldUpdate as zero when none present' {
            $summary.WouldUpdate | Should -Be 0
        }
    }

    Context 'Single result type' {
        It 'Should count a single Created result' {
            $results = @([PSCustomObject]@{ Action = 'Created' })
            $result = Get-ResultSummary -Results $results
            $result.Created | Should -Be 1
            $result.Updated | Should -Be 0
        }
    }

    Context 'Unknown action values' {
        It 'Should ignore unknown Action values' {
            $results = @(
                [PSCustomObject]@{ Action = 'Created' }
                [PSCustomObject]@{ Action = 'InvalidAction' }
                [PSCustomObject]@{ Action = 'SomethingElse' }
            )
            $result = Get-ResultSummary -Results $results
            $result.Created | Should -Be 1
            $result.Keys | Should -Not -Contain 'InvalidAction'
        }

        It 'Should ignore results with null Action' {
            $results = @(
                [PSCustomObject]@{ Action = $null }
                [PSCustomObject]@{ Action = 'Created' }
            )
            $result = Get-ResultSummary -Results $results
            $result.Created | Should -Be 1
        }
    }

    Context 'Return type' {
        It 'Should return a hashtable' {
            $result = Get-ResultSummary -Results @()
            $result | Should -BeOfType [hashtable]
        }

        It 'Should contain all 8 expected keys' {
            $result = Get-ResultSummary -Results @()
            $result.Keys | Should -HaveCount 8
        }
    }
}
