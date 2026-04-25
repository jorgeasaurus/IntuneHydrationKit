#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Write-HydrationExecutionSummary.ps1
}

Describe 'Write-HydrationExecutionSummary' {
    BeforeEach {
        Mock Write-HydrationLog { }
        Mock Get-ResultSummary {
            @{
                Created     = 1
                Updated     = 2
                Deleted     = 3
                Skipped     = 4
                Failed      = 0
                WouldCreate = 5
                WouldUpdate = 6
                WouldDelete = 7
            }
        }
        Mock Write-Information { }
    }

    It 'Should emit summary lines through the information stream in dry-run mode' {
        $settings = @{
            tenant         = @{ tenantId = '12345678-1234-1234-1234-123456789abc' }
            authentication = @{ environment = 'Global' }
            reporting      = @{ outputPath = 'TestDrive:\Reports'; formats = @('markdown', 'json') }
        }
        $expectedMarkdownPath = Join-Path -Path 'TestDrive:\Reports' -ChildPath 'Hydration-Summary.md'
        $expectedJsonPath = Join-Path -Path 'TestDrive:\Reports' -ChildPath 'Hydration-Summary.json'

        $result = Write-HydrationExecutionSummary -Settings $settings -Results @() -WhatIfEnabled $true

        $result.ReportPath | Should -Be $expectedMarkdownPath
        $result.JsonReportPath | Should -Be $expectedJsonPath
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq '---------------- Summary ----------------' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq 'Would Create: 5 | Would Update: 6 | Would Delete: 7 | Skipped: 4 | Failed: 0' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq "Reports: $expectedMarkdownPath" } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq "JSON:    $expectedJsonPath" } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq '' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq '----------------------------------------' } -Times 1
        Should -Invoke Write-Information -Exactly 6
    }
}
