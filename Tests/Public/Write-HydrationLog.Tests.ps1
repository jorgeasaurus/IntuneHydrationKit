#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Public/Write-HydrationLog.ps1
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
            $MessageData -eq '  [i] Importing policies'
        }
    }

    It 'Should suppress debug console output when verbose logging is disabled' {
        Mock Write-Information { }

        Write-HydrationLog -Message 'Debug details' -Level Debug

        Should -Invoke Write-Information -Exactly 0
    }
}
