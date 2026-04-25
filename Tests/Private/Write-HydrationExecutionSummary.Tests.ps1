#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Format-HydrationDisplayMessage.ps1
    . $PSScriptRoot/../../Private/Write-HydrationExecutionSummary.ps1

    function Remove-AnsiFormatting {
        param([string]$Text)

        $escapePattern = [regex]::Escape([string][char]27) + '\[[0-9;]*m'
        return ($Text -replace $escapePattern, '')
    }
}

Describe 'Write-HydrationExecutionSummary' {
    BeforeEach {
        Mock Write-HydrationLog { }
        Mock Get-Date { [datetime]'2026-04-24T22:02:03' }
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
        $startTime = [datetime]'2026-04-24T21:00:00'
        $expectedMarkdownPath = Join-Path -Path 'TestDrive:\Reports' -ChildPath 'Hydration-Summary.md'
        $expectedJsonPath = Join-Path -Path 'TestDrive:\Reports' -ChildPath 'Hydration-Summary.json'

        $result = Write-HydrationExecutionSummary -Settings $settings -Results @() -StartTime $startTime -WhatIfEnabled $true

        $result.ReportPath | Should -Be $expectedMarkdownPath
        $result.JsonReportPath | Should -Be $expectedJsonPath
        $result.ElapsedTimeDisplay | Should -Be '01:02:03'
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '📊 Hydration Summary' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '🧪 Would Create: 5 | Would Update: 6 | Would Delete: 7 | Skipped: 4 | Failed: 0' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '⏱️ Elapsed: 01:02:03' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq "📝 Reports: $expectedMarkdownPath" } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq "🧾 JSON:    $expectedJsonPath" } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq '' } -Times 1
        Should -Invoke Write-Information -Exactly 6
    }
}

