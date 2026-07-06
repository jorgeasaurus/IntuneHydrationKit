#Requires -Modules Pester

Describe 'Build configuration' {
    BeforeAll {
        $script:RepoRoot = Join-Path $PSScriptRoot '..'
    }

    It 'Should package settings.schema.json with the built module' {
        $buildScript = Get-Content -Path (Join-Path $script:RepoRoot 'IntuneHydrationKit.build.ps1') -Raw

        $buildScript | Should -Match "'settings\.schema\.json'"
    }

    It 'Should run the default build task when Task is omitted' {
        $bootstrapScript = Get-Content -Path (Join-Path $script:RepoRoot 'build.ps1') -Raw

        $bootstrapScript | Should -Match 'if \(-not \$Task\)'
        $bootstrapScript | Should -Match '\$Task = @\(''\.''\)'
    }

    It 'Should bootstrap CI without running the default build twice' {
        $workflow = Get-Content -Path (Join-Path $script:RepoRoot '.github/workflows/ci.yml') -Raw

        $workflow | Should -Match '\./build\.ps1 -NoBuild'
    }

    It 'Should keep public function exports in sync' {
        $syncScript = Join-Path $script:RepoRoot 'scripts/Sync-PublicFunctionExports.ps1'

        $output = & pwsh -NoLogo -NoProfile -File $syncScript -CheckOnly 2>&1

        $output | Out-String | Should -Match 'already in sync'
        $LASTEXITCODE | Should -Be 0
    }

    It 'Should treat CRLF-normalized public function exports as in sync' {
        $fixtureRoot = Join-Path $TestDrive 'ExportSyncCrlf'
        $scriptDirectory = Join-Path $fixtureRoot 'scripts'
        $publicDirectory = Join-Path $fixtureRoot 'Public'
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

        New-Item -Path $scriptDirectory -ItemType Directory -Force | Out-Null
        New-Item -Path $publicDirectory -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $script:RepoRoot 'scripts/Sync-PublicFunctionExports.ps1') -Destination (Join-Path $scriptDirectory 'Sync-PublicFunctionExports.ps1')

        [System.IO.File]::WriteAllText(
            (Join-Path $publicDirectory 'Invoke-Example.ps1'),
            "function Invoke-Example {}`r`n",
            $utf8NoBom
        )

        $expectedExports = @(
            'Get-GraphErrorMessage'
            'Get-ObfuscatedTenantId'
            'Get-ResultSummary'
            'Invoke-Example'
            'New-HydrationResult'
            'Test-HydrationKitObject'
        ) | Sort-Object -Unique

        $newLine = "`r`n"
        $functionListText = ($expectedExports | ForEach-Object { "        '$_'" }) -join ",$newLine"
        $manifestContent = @(
            '@{'
            '    FunctionsToExport = @('
            $functionListText
            '    )'
            ''
            '    # Cmdlets to export from this module'
            '    CmdletsToExport = @()'
            '}'
            ''
        ) -join $newLine
        $moduleContent = @(
            '$publicFunctions = @('
            $functionListText
            ')'
            ''
            '# Export functions'
            ''
        ) -join $newLine

        [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'IntuneHydrationKit.psd1'), $manifestContent, $utf8NoBom)
        [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'IntuneHydrationKit.psm1'), $moduleContent, $utf8NoBom)

        $output = & pwsh -NoLogo -NoProfile -File (Join-Path $scriptDirectory 'Sync-PublicFunctionExports.ps1') -CheckOnly 2>&1

        $output | Out-String | Should -Match 'already in sync'
        $LASTEXITCODE | Should -Be 0
    }

    It 'Should preserve intentional helper exports in the sync script' {
        $syncScript = Get-Content -Path (Join-Path $script:RepoRoot 'scripts/Sync-PublicFunctionExports.ps1') -Raw

        $syncScript | Should -Match "'New-HydrationResult'"
        $syncScript | Should -Match "'Get-ResultSummary'"
        $syncScript | Should -Match "'Get-GraphErrorMessage'"
        $syncScript | Should -Match "'Test-HydrationKitObject'"
        $syncScript | Should -Match "'Get-ObfuscatedTenantId'"
    }
}
