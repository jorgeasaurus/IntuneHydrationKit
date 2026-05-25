#Requires -Modules Pester

Describe 'Sync-PublicFunctionExports.ps1' {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'export-sync'
        $script:scriptsPath = Join-Path $script:testRoot 'scripts'
        $script:publicPath = Join-Path $script:testRoot 'Public'
        $null = New-Item -Path $script:scriptsPath -ItemType Directory -Force
        $null = New-Item -Path $script:publicPath -ItemType Directory -Force

        Copy-Item -Path (Join-Path $PSScriptRoot '../../scripts/Sync-PublicFunctionExports.ps1') -Destination (Join-Path $script:scriptsPath 'Sync-PublicFunctionExports.ps1')
        '' | Set-Content -Path (Join-Path $script:publicPath 'Invoke-TestFunction.ps1') -Encoding utf8
    }

    It 'Should throw when the manifest export block anchor is missing' {
        Set-Content -Path (Join-Path $script:testRoot 'IntuneHydrationKit.psd1') -Encoding utf8 -Value @'
@{
    FunctionsToExport = @(
        'Invoke-OldFunction'
    )
}
'@

        Set-Content -Path (Join-Path $script:testRoot 'IntuneHydrationKit.psm1') -Encoding utf8 -Value @'
$publicFunctions = @(
    'Invoke-OldFunction'
)

# Export functions
'@

        { & (Join-Path $script:scriptsPath 'Sync-PublicFunctionExports.ps1') -CheckOnly } |
            Should -Throw '*Could not locate FunctionsToExport block in module manifest*'
    }

    It 'Should throw when the module export block anchor is missing' {
        Set-Content -Path (Join-Path $script:testRoot 'IntuneHydrationKit.psd1') -Encoding utf8 -Value @'
@{
    FunctionsToExport = @(
        'Invoke-OldFunction'
    )

    # Cmdlets to export from this module
}
'@

        Set-Content -Path (Join-Path $script:testRoot 'IntuneHydrationKit.psm1') -Encoding utf8 -Value @'
$publicFunctions = @(
    'Invoke-OldFunction'
)
'@

        { & (Join-Path $script:scriptsPath 'Sync-PublicFunctionExports.ps1') -CheckOnly } |
            Should -Throw '*Could not locate publicFunctions export block in module file*'
    }
}
