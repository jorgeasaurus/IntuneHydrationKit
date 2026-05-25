#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Hydration/Save-HydrationGeneratedScript.ps1

    function Write-HydrationLog {
        param(
            [string]$Message,
            [string]$Level
        )

        $null = $Message
        $null = $Level
    }
}

Describe 'Save-HydrationGeneratedScript' {
    BeforeEach {
        $script:GeneratedScriptsPath = Join-Path -Path $TestDrive -ChildPath 'GeneratedScripts'
        $script:GeneratedScriptsNoticeWritten = $false
        $script:HydrationSessionId = 'test-session'
    }

    AfterEach {
        $script:GeneratedScriptsPath = $null
        $script:GeneratedScriptsNoticeWritten = $false
        $script:HydrationSessionId = $null
    }

    It 'Should write content to a nested generated script path' {
        $result = Save-HydrationGeneratedScript -RelativePath 'WinGetApps/contoso/Install.ps1' -Content 'Write-Output "install"'

        $result | Should -Be (Join-Path -Path $script:GeneratedScriptsPath -ChildPath 'WinGetApps/contoso/Install.ps1')
        $result | Should -Exist
        Get-Content -Path $result -Raw | Should -Match 'Write-Output "install"'
    }

    It 'Should copy source files to nested generated script paths' {
        $sourcePath = Join-Path -Path 'TestDrive:' -ChildPath 'Source.ps1'
        Set-Content -Path $sourcePath -Value 'Write-Output "source"' -Encoding utf8

        $result = Save-HydrationGeneratedScript -RelativePath 'WinGetApps/contoso/Detection/Detect.ps1' -SourcePath $sourcePath

        $result | Should -Exist
        Get-Content -Path $result -Raw | Should -Match 'Write-Output "source"'
    }

    It 'Should throw a clear error when SourcePath is missing' {
        $missingSourcePath = Join-Path -Path 'TestDrive:' -ChildPath 'Missing.ps1'

        { Save-HydrationGeneratedScript -RelativePath 'WinGetApps/contoso/Install.ps1' -SourcePath $missingSourcePath } |
            Should -Throw -ExpectedMessage "SourcePath must be an existing file: $missingSourcePath"
    }

    It 'Should reject rooted generated script paths' {
        $rootedPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'Escape.ps1'

        { Save-HydrationGeneratedScript -RelativePath $rootedPath -Content 'Write-Output "escape"' } |
            Should -Throw -ExpectedMessage 'RelativePath must not be rooted.'
    }

    It 'Should reject generated script path traversal' {
        { Save-HydrationGeneratedScript -RelativePath '../Escape.ps1' -Content 'Write-Output "escape"' } |
            Should -Throw -ExpectedMessage 'RelativePath must stay within the generated scripts directory.'
    }

    It 'Should make filesystem writes terminating' {
        $source = Get-Content -Path "$PSScriptRoot/../../Private/Hydration/Save-HydrationGeneratedScript.ps1" -Raw

        $source | Should -Match 'New-Item[\s\S]+-ErrorAction Stop'
        $source | Should -Match 'Copy-Item[\s\S]+-ErrorAction Stop'
        $source | Should -Match 'Set-Content[\s\S]+-ErrorAction Stop'
    }
}
