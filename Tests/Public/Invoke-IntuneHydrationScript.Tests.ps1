#Requires -Modules Pester

Describe 'Invoke-IntuneHydration.ps1 wrapper script' {
    BeforeAll {
        $script:RepositoryRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
        $script:WrapperScriptPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'Invoke-IntuneHydration.ps1'
    }

    It 'imports the local module and forwards bound parameters to Invoke-IntuneHydration' {
        $sandboxPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('IHKWrapperTest-{0}' -f [guid]::NewGuid().ToString('N'))
        $capturePath = Join-Path -Path $sandboxPath -ChildPath 'capture.json'

        try {
            New-Item -Path $sandboxPath -ItemType Directory -Force | Out-Null
            Copy-Item -Path $script:WrapperScriptPath -Destination (Join-Path -Path $sandboxPath -ChildPath 'Invoke-IntuneHydration.ps1')

            $fakeModulePath = Join-Path -Path $sandboxPath -ChildPath 'IntuneHydrationKit.psm1'
            @'
function Invoke-IntuneHydration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [switch]$Create,

        [Parameter()]
        [switch]$MobileApps,

        [Parameter()]
        [string[]]$Platform
    )

    $capture = [ordered]@{
        TenantId = $TenantId
        Interactive = $Interactive.IsPresent
        Create = $Create.IsPresent
        MobileApps = $MobileApps.IsPresent
        Platform = @($Platform)
        WhatIf = [bool]$WhatIfPreference
    }

    [System.IO.File]::WriteAllText($env:IHK_WRAPPER_CAPTURE_PATH, ($capture | ConvertTo-Json -Compress))

    return [pscustomobject]@{
        Success = $true
    }
}

Export-ModuleMember -Function Invoke-IntuneHydration
'@ | Set-Content -Path $fakeModulePath -Encoding utf8

            New-ModuleManifest -Path (Join-Path -Path $sandboxPath -ChildPath 'IntuneHydrationKit.psd1') `
                -RootModule 'IntuneHydrationKit.psm1' `
                -ModuleVersion '0.0.1' `
                -Guid '00000000-0000-0000-0000-000000000001' `
                -FunctionsToExport @('Invoke-IntuneHydration') | Out-Null

            $env:IHK_WRAPPER_CAPTURE_PATH = $capturePath
            & pwsh -NoProfile -File (Join-Path -Path $sandboxPath -ChildPath 'Invoke-IntuneHydration.ps1') `
                -TenantId '00000000-0000-0000-0000-000000000000' `
                -Interactive `
                -Create `
                -MobileApps `
                -Platform Windows `
                -WhatIf | Out-Null

            $LASTEXITCODE | Should -Be 0
            Test-Path -Path $capturePath | Should -BeTrue

            $capture = Get-Content -Path $capturePath -Raw -Encoding utf8 | ConvertFrom-Json
            $capture.TenantId | Should -Be '00000000-0000-0000-0000-000000000000'
            $capture.Interactive | Should -BeTrue
            $capture.Create | Should -BeTrue
            $capture.MobileApps | Should -BeTrue
            $capture.Platform | Should -Be @('Windows')
            $capture.WhatIf | Should -BeTrue
        } finally {
            Remove-Item -Path Env:\IHK_WRAPPER_CAPTURE_PATH -ErrorAction SilentlyContinue

            if (Test-Path -Path $sandboxPath) {
                Remove-Item -Path $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
