#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Hydration/Format-HydrationDisplayMessage.ps1
    . $PSScriptRoot/../../Public/Logging/Write-HydrationLog.ps1

    function Remove-AnsiFormatting {
        param([string]$Text)

        $escapePattern = [regex]::Escape([string][char]27) + '\[[0-9;]*m'
        return ($Text -replace $escapePattern, '')
    }
}

Describe 'Write-HydrationLog' {
    BeforeEach {
        $script:CurrentLogFile = $null
        $script:VerboseLogging = $false
    }

    It 'Should emit informational messages through the information stream' {
        Mock Write-Information { }

        Write-HydrationLog -Message 'Importing policies' -Level Info

        Should -Invoke Write-Information -Exactly 1 -ParameterFilter {
            (Remove-AnsiFormatting -Text $MessageData) -eq '  ℹ️ Importing policies'
        }
    }

    It 'Should suppress debug console output when verbose logging is disabled' {
        Mock Write-Information { }

        Write-HydrationLog -Message 'Debug details' -Level Debug

        Should -Invoke Write-Information -Exactly 0
    }
}
