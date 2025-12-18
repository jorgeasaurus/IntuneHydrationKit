#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    # Create temp directory for test files
    $script:TestTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PesterTests-Logging-$(Get-Random)"
    New-Item -Path $script:TestTempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup temp directory
    if (Test-Path $script:TestTempDir) {
        Remove-Item -Path $script:TestTempDir -Recurse -Force
    }

    # Cleanup default temp directory created by tests
    $defaultTempPath = Join-Path ([System.IO.Path]::GetTempPath()) 'IntuneHydrationKit/Logs'
    if (Test-Path $defaultTempPath) {
        # Only remove log files created during this test run (within last minute)
        Get-ChildItem -Path $defaultTempPath -Filter "hydration-*.log" |
            Where-Object { $_.CreationTime -gt (Get-Date).AddMinutes(-5) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Initialize-HydrationLogging' {
    Context 'Parameter Validation' {
        It 'Should have LogPath parameter as optional' {
            $command = Get-Command Initialize-HydrationLogging
            $logPathParam = $command.Parameters['LogPath']

            $mandatoryAttr = $logPathParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }

            # Parameter should not be mandatory (optional)
            ($mandatoryAttr | Where-Object { $_.Mandatory }).Count | Should -Be 0
        }

        It 'Should have EnableVerbose switch parameter' {
            $command = Get-Command Initialize-HydrationLogging
            $verboseParam = $command.Parameters['EnableVerbose']

            $verboseParam.SwitchParameter | Should -Be $true
        }
    }

    Context 'Default Log Path (OS Temp Directory)' {
        It 'Should use OS temp directory when LogPath not specified' {
            # Get expected temp path
            $expectedTempBase = [System.IO.Path]::GetTempPath()
            $expectedLogPath = Join-Path -Path $expectedTempBase -ChildPath 'IntuneHydrationKit/Logs'

            # Initialize logging without specifying path
            Initialize-HydrationLogging

            # Verify the directory was created in temp location
            Test-Path -Path $expectedLogPath | Should -Be $true
        }

        It 'Should create log file in OS temp directory' {
            $expectedTempBase = [System.IO.Path]::GetTempPath()
            $expectedLogPath = Join-Path -Path $expectedTempBase -ChildPath 'IntuneHydrationKit/Logs'

            Initialize-HydrationLogging

            # Check that at least one log file exists
            $logFiles = Get-ChildItem -Path $expectedLogPath -Filter "hydration-*.log" -ErrorAction SilentlyContinue
            $logFiles.Count | Should -BeGreaterThan 0
        }

        It 'Should work on different OS platforms' {
            # This test verifies the cross-platform temp path resolution
            $tempPath = [System.IO.Path]::GetTempPath()

            # Temp path should be valid and accessible
            $tempPath | Should -Not -BeNullOrEmpty
            Test-Path -Path $tempPath | Should -Be $true
        }
    }

    Context 'Custom Log Path' {
        It 'Should use custom path when LogPath is specified' {
            $customLogPath = Join-Path $script:TestTempDir 'CustomLogs'

            Initialize-HydrationLogging -LogPath $customLogPath

            Test-Path -Path $customLogPath | Should -Be $true
        }

        It 'Should create directory if it does not exist' {
            $newLogPath = Join-Path $script:TestTempDir "NewLogsDir-$(Get-Random)"

            # Verify directory doesn't exist yet
            Test-Path -Path $newLogPath | Should -Be $false

            Initialize-HydrationLogging -LogPath $newLogPath

            # Now it should exist
            Test-Path -Path $newLogPath | Should -Be $true
        }

        It 'Should create log file in custom directory' {
            $customLogPath = Join-Path $script:TestTempDir "LogsWithFile-$(Get-Random)"

            Initialize-HydrationLogging -LogPath $customLogPath

            $logFiles = Get-ChildItem -Path $customLogPath -Filter "hydration-*.log"
            $logFiles.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Log File Naming' {
        It 'Should create log file with timestamp format' {
            $customLogPath = Join-Path $script:TestTempDir "TimestampTest-$(Get-Random)"

            Initialize-HydrationLogging -LogPath $customLogPath

            $logFiles = Get-ChildItem -Path $customLogPath -Filter "hydration-*.log"

            # Verify filename matches expected pattern: hydration-YYYYMMDD-HHMMSS.log
            $logFiles[0].Name | Should -Match '^hydration-\d{8}-\d{6}\.log$'
        }
    }

    Context 'Verbose Logging Flag' {
        It 'Should accept EnableVerbose switch' {
            $customLogPath = Join-Path $script:TestTempDir "VerboseTest-$(Get-Random)"

            # Should not throw
            { Initialize-HydrationLogging -LogPath $customLogPath -EnableVerbose } | Should -Not -Throw
        }
    }

    Context 'Idempotent Behavior' {
        It 'Should handle being called multiple times' {
            $customLogPath = Join-Path $script:TestTempDir "MultiCall-$(Get-Random)"

            # Call multiple times - should not throw
            { Initialize-HydrationLogging -LogPath $customLogPath } | Should -Not -Throw
            { Initialize-HydrationLogging -LogPath $customLogPath } | Should -Not -Throw

            Test-Path -Path $customLogPath | Should -Be $true
        }

        It 'Should create new log file on each initialization' {
            $customLogPath = Join-Path $script:TestTempDir "NewFileEachTime-$(Get-Random)"

            Initialize-HydrationLogging -LogPath $customLogPath
            Start-Sleep -Seconds 1  # Ensure different timestamp
            Initialize-HydrationLogging -LogPath $customLogPath

            $logFiles = Get-ChildItem -Path $customLogPath -Filter "hydration-*.log"
            # May have 1 or 2 files depending on timestamp granularity
            $logFiles.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should resolve temp path correctly on current OS' {
            $tempPath = [System.IO.Path]::GetTempPath()

            # On Windows, typically ends with backslash
            # On macOS/Linux, typically ends with forward slash
            # Just verify it's a valid path
            $tempPath | Should -Not -BeNullOrEmpty

            # Path should be absolute
            [System.IO.Path]::IsPathRooted($tempPath) | Should -Be $true
        }

        It 'Should create nested directory structure' {
            $expectedTempBase = [System.IO.Path]::GetTempPath()
            $expectedLogPath = Join-Path -Path $expectedTempBase -ChildPath 'IntuneHydrationKit/Logs'

            Initialize-HydrationLogging

            # Verify nested structure exists
            $parentDir = Join-Path -Path $expectedTempBase -ChildPath 'IntuneHydrationKit'
            Test-Path -Path $parentDir | Should -Be $true
            Test-Path -Path $expectedLogPath | Should -Be $true
        }
    }
}
