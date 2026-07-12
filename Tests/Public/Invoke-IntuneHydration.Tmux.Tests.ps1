#Requires -Modules Pester

Describe 'Invoke-IntuneHydration tmux TUI invocation' -Tag 'Tmux' -Skip:(-not (Get-Command tmux -ErrorAction SilentlyContinue) -or $env:IHK_RUN_TMUX_TESTS -ne '1') {
    BeforeAll {
        $script:ModuleRoot = Join-Path $PSScriptRoot '..' '..'
        $script:ModulePath = Join-Path $script:ModuleRoot 'IntuneHydrationKit.psd1'
        $script:TmuxPath = (Get-Command tmux -ErrorAction Stop).Source
        $script:TmuxTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "IntuneHydrationKitTmuxTests-$PID"
        New-Item -Path $script:TmuxTestRoot -ItemType Directory -Force | Out-Null

        function ConvertTo-TestPowerShellLiteral {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Value
            )

            return "'$($Value -replace "'", "''")'"
        }

        function Expand-TestScriptTemplate {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Template,

                [Parameter(Mandatory)]
                [hashtable]$Value
            )

            $expanded = $Template
            foreach ($item in $Value.GetEnumerator()) {
                $expanded = $expanded.Replace($item.Key, (ConvertTo-TestPowerShellLiteral -Value $item.Value))
            }

            return $expanded
        }

        function Test-TestTmuxSession {
            [CmdletBinding()]
            [OutputType([bool])]
            param(
                [Parameter(Mandatory)]
                [string]$SessionName
            )

            & $script:TmuxPath has-session -t $SessionName 2>$null
            return $LASTEXITCODE -eq 0
        }

        function Send-TestTmuxKey {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$SessionName,

                [Parameter(Mandatory)]
                [string]$Key
            )

            if ($Key.StartsWith('literal:', [System.StringComparison]::Ordinal)) {
                & $script:TmuxPath send-keys -t $SessionName -l $Key.Substring('literal:'.Length)
            } else {
                & $script:TmuxPath send-keys -t $SessionName $Key
            }
        }

        function Invoke-TestTmuxScript {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$ScriptText,

                [Parameter(Mandatory)]
                [string[]]$Keys,

                [Parameter()]
                [int]$TimeoutSeconds = 15
            )

            $sessionName = "ihk-tui-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
            $scriptPath = Join-Path $script:TmuxTestRoot "$sessionName.ps1"
            $outputPath = Join-Path $script:TmuxTestRoot "$sessionName.json"
            $donePath = Join-Path $script:TmuxTestRoot "$sessionName.done"
            $expandedScript = Expand-TestScriptTemplate -Template $ScriptText -Value @{
                '__MODULE_PATH__' = $script:ModulePath
                '__OUTPUT_PATH__' = $outputPath
                '__DONE_PATH__'   = $donePath
            }

            Set-Content -Path $scriptPath -Value $expandedScript -Encoding utf8

            try {
                & $script:TmuxPath new-session -d -s $sessionName -x 140 -y 45 pwsh -NoLogo -NoProfile -File $scriptPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to start tmux session '$sessionName'."
                }

                Start-Sleep -Milliseconds 500
                foreach ($key in $Keys) {
                    Send-TestTmuxKey -SessionName $sessionName -Key $key
                    Start-Sleep -Milliseconds 150
                }

                $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
                while ((-not (Test-Path -Path $donePath)) -and [DateTime]::UtcNow -lt $deadline) {
                    if (-not (Test-TestTmuxSession -SessionName $sessionName)) {
                        break
                    }

                    Start-Sleep -Milliseconds 200
                }

                $paneText = if (Test-TestTmuxSession -SessionName $sessionName) {
                    (& $script:TmuxPath capture-pane -p -t $sessionName) -join "`n"
                } else {
                    ''
                }

                if (-not (Test-Path -Path $donePath)) {
                    throw "tmux TUI script did not finish within $TimeoutSeconds seconds. Pane output: $paneText"
                }

                if (-not (Test-Path -Path $outputPath)) {
                    throw "tmux TUI script did not write an output file. Pane output: $paneText"
                }

                $result = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
                if (-not $result.Success) {
                    throw "tmux TUI script failed: $($result.Error)"
                }

                return $result
            } finally {
                if (Test-TestTmuxSession -SessionName $sessionName) {
                    & $script:TmuxPath kill-session -t $sessionName 2>$null
                }
            }
        }
    }

    AfterAll {
        if (Test-Path -Path $script:TmuxTestRoot) {
            Remove-Item -Path $script:TmuxTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should route zero-argument invocation through the TUI and cancel before Graph calls' {
        $scriptText = @'
$ErrorActionPreference = 'Stop'
$modulePath = __MODULE_PATH__
$outputPath = __OUTPUT_PATH__
$donePath = __DONE_PATH__

try {
    Import-Module -Name $modulePath -Force
    $records = @(Invoke-IntuneHydration 3>&1 4>&1 6>&1)
    $warnings = @(
        $records |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
            ForEach-Object { $_.Message }
    )

    [pscustomobject]@{
        Success         = $true
        WarningMessages = $warnings
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $outputPath -Encoding utf8
} catch {
    [pscustomobject]@{
        Success = $false
        Error   = $_.Exception.Message
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $outputPath -Encoding utf8
} finally {
    Set-Content -Path $donePath -Value 'done' -Encoding utf8
}
'@

        $result = Invoke-TestTmuxScript -ScriptText $scriptText -Keys @('literal:q', 'Enter')

        $result.WarningMessages | Should -Contain 'Interactive setup cancelled. No hydration actions were run.'
    }

    It 'Should complete the TUI selection flow and return selected settings' {
        $scriptText = @'
$ErrorActionPreference = 'Stop'
$modulePath = __MODULE_PATH__
$outputPath = __OUTPUT_PATH__
$donePath = __DONE_PATH__

try {
    $module = Import-Module -Name $modulePath -Force -PassThru
    $selection = & $module {
        $tuiSelection = Invoke-HydrationTui
        [pscustomobject]@{
            Environment          = $tuiSelection.Environment
            Create               = [bool]$tuiSelection.Operation.create
            Delete               = [bool]$tuiSelection.Operation.delete
            DryRun               = [bool]$tuiSelection.Operation.dryRun
            DeviceFilters        = [bool]$tuiSelection.Imports.deviceFilters
            DynamicGroups        = [bool]$tuiSelection.Imports.dynamicGroups
            Platforms            = @($tuiSelection.Platforms)
            ConsentPromptEnabled = [bool]$tuiSelection.ConsentPromptEnabled
            VerboseEnabled       = [bool]$tuiSelection.VerboseEnabled
        }
    }

    [pscustomobject]@{
        Success   = $true
        Selection = $selection
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $outputPath -Encoding utf8
} catch {
    [pscustomobject]@{
        Success = $false
        Error   = $_.Exception.Message
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $outputPath -Encoding utf8
} finally {
    Set-Content -Path $donePath -Value 'done' -Encoding utf8
}
'@

        $keys = @(
            'Enter'
            'Down'
            'Enter'
            'Down'
            'Down'
            'Space'
            'Enter'
            'Down'
            'Space'
            'Enter'
            'literal:y'
            'Enter'
            'literal:y'
            'Enter'
        )
        $result = Invoke-TestTmuxScript -ScriptText $scriptText -Keys $keys

        $result.Selection.Environment | Should -Be 'Global'
        $result.Selection.Create | Should -BeTrue
        $result.Selection.Delete | Should -BeFalse
        $result.Selection.DryRun | Should -BeTrue
        $result.Selection.DeviceFilters | Should -BeTrue
        $result.Selection.DynamicGroups | Should -BeFalse
        $result.Selection.Platforms | Should -Be @('Windows')
        $result.Selection.ConsentPromptEnabled | Should -BeTrue
        $result.Selection.VerboseEnabled | Should -BeTrue
    }
}
