#Requires -Modules Pester

BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..' '..'
    Get-Module -Name IntuneHydrationKit -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:ModuleRoot 'IntuneHydrationKit.psd1') -Force

    $script:TestTempPath = Join-Path ([System.IO.Path]::GetTempPath()) 'IntuneHydrationKitTuiTests'
    if (-not (Test-Path $script:TestTempPath)) {
        New-Item -Path $script:TestTempPath -ItemType Directory -Force | Out-Null
    }
}

AfterAll {
    if (Test-Path $script:TestTempPath) {
        Remove-Item -Path $script:TestTempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-IntuneHydration TUI entry point' {
    Context 'Repository wrapper metadata' {
        It 'Should allow zero-argument wrapper invocation through the TUI parameter set' {
            $wrapperPath = Join-Path $script:ModuleRoot 'Invoke-IntuneHydration.ps1'
            $command = Get-Command $wrapperPath
            $interactiveTuiSet = $command.ParameterSets |
                Where-Object { $_.Name -eq 'InteractiveTui' } |
                Select-Object -First 1

            $interactiveTuiSet | Should -Not -BeNullOrEmpty
            $interactiveTuiSet.IsDefault | Should -BeTrue
            $settingsFileSet = $command.Parameters['SettingsPath'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'SettingsFile' }
            $settingsFileSet.Mandatory | Should -Be $true
        }

        It 'Should keep wrapper parameters aligned with module parameters' {
            $commonParameters = @(
                'Verbose'
                'Debug'
                'ErrorAction'
                'WarningAction'
                'InformationAction'
                'ProgressAction'
                'ErrorVariable'
                'WarningVariable'
                'InformationVariable'
                'OutVariable'
                'OutBuffer'
                'PipelineVariable'
                'WhatIf'
                'Confirm'
            )
            $moduleCommand = Get-Command Invoke-IntuneHydration
            $wrapperCommand = Get-Command (Join-Path $script:ModuleRoot 'Invoke-IntuneHydration.ps1')
            $moduleParameters = @($moduleCommand.Parameters.Keys | Where-Object { $_ -notin $commonParameters } | Sort-Object)
            $wrapperParameters = @($wrapperCommand.Parameters.Keys | Where-Object { $_ -notin $commonParameters } | Sort-Object)

            Compare-Object -ReferenceObject $moduleParameters -DifferenceObject $wrapperParameters |
                Should -BeNullOrEmpty
        }
    }

    Context 'Zero-argument TUI invocation' {
        BeforeEach {
            Mock Test-HydrationTuiHost { $true } -ModuleName IntuneHydrationKit
            Mock Invoke-HydrationTui { $null } -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiReview -ModuleName IntuneHydrationKit
            Mock Confirm-HydrationTuiChoice { $true } -ModuleName IntuneHydrationKit
            Mock Connect-IntuneHydration -ModuleName IntuneHydrationKit
            Mock Test-IntunePrerequisites -ModuleName IntuneHydrationKit
            Mock Initialize-HydrationLogging -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog -ModuleName IntuneHydrationKit
            Mock Write-HydrationExecutionSettingsSummary -ModuleName IntuneHydrationKit
            Mock Write-HydrationExecutionSummary {
                @{
                    Summary            = @{ Failed = 0 }
                    ReportPath         = $null
                    JsonReportPath     = $null
                    ElapsedTime        = [TimeSpan]::FromSeconds(3)
                    ElapsedTimeDisplay = '00:00:03'
                }
            } -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678-****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
            Mock Import-IntuneDeviceFilter { @() } -ModuleName IntuneHydrationKit
        }

        It 'Should route zero-argument invocation to the TUI helper' {
            $output = Invoke-IntuneHydration 3>&1
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $result = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })

            $result | Should -BeNullOrEmpty
            $warnings.Message | Should -Contain 'Interactive setup cancelled. No hydration actions were run.'
            Should -Invoke Test-HydrationTuiHost -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Invoke-HydrationTui -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -Times 0
        }

        It 'Should route common-parameter-only invocation to the TUI helper' {
            $output = & { Invoke-IntuneHydration -Verbose } 3>&1 4>$null
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $result = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })

            $result | Should -BeNullOrEmpty
            $warnings.Message | Should -Contain 'Interactive setup cancelled. No hydration actions were run.'
            Should -Invoke Invoke-HydrationTui -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -Times 0
        }

        It 'Should throw clear guidance for non-interactive zero-argument invocation' {
            Mock Test-HydrationTuiHost { $false } -ModuleName IntuneHydrationKit

            { Invoke-IntuneHydration } |
                Should -Throw '*requires an interactive console*'

            Should -Invoke Invoke-HydrationTui -ModuleName IntuneHydrationKit -Times 0
        }

        It 'Should execute existing orchestration when TUI returns confirmed selections' {
            Mock Invoke-HydrationTui {
                @{
                    Environment    = 'USGov'
                    Operation      = @{ create = $true; delete = $false; dryRun = $true }
                    Imports        = @{
                        dynamicGroups         = $false
                        staticGroups          = $false
                        deviceFilters         = $true
                        openIntuneBaseline    = $false
                        cisBaselines          = $false
                        complianceTemplates   = $false
                        appProtection         = $false
                        notificationTemplates = $false
                        enrollmentProfiles    = $false
                        conditionalAccess     = $false
                        mobileApps            = $false
                    }
                    Platforms      = @('All')
                    VerboseEnabled = $false
                }
            } -ModuleName IntuneHydrationKit

            Invoke-IntuneHydration | Out-Null

            Should -Invoke Invoke-HydrationTui -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Show-HydrationTuiReview -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Confirm-HydrationTuiChoice -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $Prompt -eq 'Run hydration with these settings?' -and
                $ClearScreen -eq $false
            }
            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $null -eq $TenantId -and
                $Interactive -eq $true -and
                $Environment -eq 'USGov'
            }
            Should -Invoke Test-IntunePrerequisites -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneDeviceFilter -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $WhatIf -eq $true
            }
        }

        It 'Should pass forced consent when selected in the TUI' {
            Mock Invoke-HydrationTui {
                @{
                    Environment          = 'Global'
                    Operation            = @{ create = $true; delete = $false; dryRun = $true }
                    Imports              = @{ deviceFilters = $true }
                    Platforms            = @('All')
                    ConsentPromptEnabled = $true
                    VerboseEnabled       = $false
                }
            } -ModuleName IntuneHydrationKit

            Invoke-IntuneHydration | Out-Null

            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $ForceConsent -eq $true
            }
        }

        It 'Should not run hydration when final TUI confirmation is declined' {
            Mock Invoke-HydrationTui {
                @{
                    Environment    = 'Global'
                    Operation      = @{ create = $true; delete = $false; dryRun = $true }
                    Imports        = @{ deviceFilters = $true }
                    Platforms      = @('All')
                    VerboseEnabled = $false
                }
            } -ModuleName IntuneHydrationKit
            Mock Confirm-HydrationTuiChoice { $false } -ModuleName IntuneHydrationKit

            $output = Invoke-IntuneHydration 3>&1
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $warnings.Message | Should -Contain 'Interactive setup cancelled. No hydration actions were run.'
            Should -Invoke Show-HydrationTuiReview -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -Times 0
        }

        It 'Should not route settings-file invocation to TUI' {
            $testSettingsPath = Join-Path $script:TestTempPath 'settings-no-tui.json'
            '{}' | Set-Content -Path $testSettingsPath -Encoding utf8

            Mock Import-HydrationSettings {
                @{
                    tenant         = @{ tenantId = '12345678-1234-1234-1234-123456789abc' }
                    authentication = @{ mode = 'interactive'; environment = 'Global' }
                    options        = @{ create = $true; delete = $false; dryRun = $true; verbose = $false }
                    imports        = @{ deviceFilters = $true }
                    reporting      = @{ formats = @('markdown') }
                }
            } -ModuleName IntuneHydrationKit

            Invoke-IntuneHydration -SettingsPath $testSettingsPath | Out-Null

            Should -Invoke Invoke-HydrationTui -ModuleName IntuneHydrationKit -Times 0
            Should -Invoke Show-HydrationTuiReview -ModuleName IntuneHydrationKit -Times 0
        }

        It 'Should not route parameter invocation to TUI' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf | Out-Null

            Should -Invoke Invoke-HydrationTui -ModuleName IntuneHydrationKit -Times 0
            Should -Invoke Show-HydrationTuiReview -ModuleName IntuneHydrationKit -Times 0
        }
    }
}
