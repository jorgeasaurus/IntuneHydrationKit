#Requires -Modules Pester

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..' '..'
    Get-Module -Name IntuneHydrationKit -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $moduleRoot 'IntuneHydrationKit.psd1') -Force

    InModuleScope IntuneHydrationKit {
        $script:GetTestHydrationTuiOption = {
            param(
                [Parameter(Mandatory)]
                [object[]]$Options,

                [Parameter(Mandatory)]
                [int[]]$Number
            )

            @($Options | Where-Object { $_.Number -in $Number })
        }

        $script:NewTestHydrationTuiOperation = {
            param(
                [Parameter()]
                [int]$Number = 2
            )

            (& $script:GetTestHydrationTuiOption -Options @(Get-HydrationTuiOperationOption) -Number $Number)[0].Options
        }

        $script:NewTestHydrationTuiImportMap = {
            param(
                [Parameter()]
                [int[]]$Number = @(3)
            )

            ConvertTo-HydrationTuiImportMap -Option (& $script:GetTestHydrationTuiOption -Options @(Get-HydrationTuiImportOption) -Number $Number)
        }

        $script:NewTestHydrationTuiSelection = {
            param(
                [Parameter()]
                [int]$OperationNumber = 2,

                [Parameter()]
                [int[]]$ImportNumber = @(3),

                [Parameter()]
                [string[]]$Platforms = @('All'),

                [Parameter()]
                [string]$Environment = 'Global',

                [Parameter()]
                [bool]$ConsentPromptEnabled = $false,

                [Parameter()]
                [bool]$VerboseEnabled = $false
            )

            @{
                Environment          = $Environment
                Operation            = & $script:NewTestHydrationTuiOperation -Number $OperationNumber
                Imports              = & $script:NewTestHydrationTuiImportMap -Number $ImportNumber
                Platforms            = $Platforms
                ConsentPromptEnabled = $ConsentPromptEnabled
                VerboseEnabled       = $VerboseEnabled
            }
        }

        $script:ResolveTestHydrationTuiSelection = {
            [CmdletBinding()]
            param(
                [Parameter()]
                [hashtable]$Selection = (& $script:NewTestHydrationTuiSelection),

                [Parameter()]
                [bool]$WhatIfEnabled,

                [Parameter()]
                [bool]$CommonVerboseEnabled
            )

            Resolve-HydrationExecutionSettings `
                -ParameterSetName 'InteractiveTui' `
                -TuiSelection $Selection `
                -WhatIfEnabled $WhatIfEnabled `
                -CommonVerboseEnabled $CommonVerboseEnabled `
                -CommandRuntime $PSCmdlet
        }
    }
}

Describe 'Hydration TUI helpers' {
    It 'Should map operation selections to existing execution options' {
        InModuleScope IntuneHydrationKit {
            $options = @(Get-HydrationTuiOperationOption)
            $create = & $script:NewTestHydrationTuiOperation -Number 1
            $dryRun = & $script:NewTestHydrationTuiOperation -Number 2
            $delete = & $script:NewTestHydrationTuiOperation -Number 3

            $options.Label | Should -Be @('Create', 'Dry-run create', 'Delete')
            $create.create | Should -BeTrue
            $create.delete | Should -BeFalse
            $create.dryRun | Should -BeFalse

            $dryRun.create | Should -BeTrue
            $dryRun.delete | Should -BeFalse
            $dryRun.dryRun | Should -BeTrue

            $delete.create | Should -BeFalse
            $delete.delete | Should -BeTrue
            $delete.dryRun | Should -BeFalse
        }
    }

    It 'Should map environment selections to Graph environments' {
        InModuleScope IntuneHydrationKit {
            $options = @(Get-HydrationTuiEnvironmentOption)

            $options.Label | Should -Be @('Global', 'US Government', 'US Government DoD', 'Germany', 'China')
            $options.Value | Should -Be @('Global', 'USGov', 'USGovDoD', 'Germany', 'China')
        }
    }

    It 'Should reject invalid operation selections' {
        InModuleScope IntuneHydrationKit {
            { Resolve-HydrationTuiOptionSelection -Options @(Get-HydrationTuiOperationOption) -Selection '9' } |
                Should -Throw '*Invalid option number*'
        }
    }

    It 'Should map selected target numbers to the existing imports shape' {
        InModuleScope IntuneHydrationKit {
            $imports = & $script:NewTestHydrationTuiImportMap -Number @(1, 3, 11)

            $imports.dynamicGroups | Should -BeTrue
            $imports.deviceFilters | Should -BeTrue
            $imports.mobileApps | Should -BeTrue
            $imports.staticGroups | Should -BeFalse
            $imports.cisBaselines | Should -BeFalse
        }
    }

    It 'Should reject an empty target selection' {
        InModuleScope IntuneHydrationKit {
            { ConvertTo-HydrationTuiImportMap -Option @() } |
                Should -Throw '*Select at least one import target*'
        }
    }

    It 'Should normalize platform selections to All or specific platforms' {
        InModuleScope IntuneHydrationKit {
            $options = @(Get-HydrationTuiPlatformOption)
            $allOption = & $script:GetTestHydrationTuiOption -Options $options -Number 0
            $mixedOptions = & $script:GetTestHydrationTuiOption -Options $options -Number @(0, 1, 2)

            $options.Label | Should -Be @('All', 'Windows', 'macOS', 'iOS', 'Android', 'Linux')
            ConvertTo-HydrationTuiPlatformList -Option @() |
                Should -Be @('All')
            ConvertTo-HydrationTuiPlatformList -Option $allOption |
                Should -Be @('All')
            ConvertTo-HydrationTuiPlatformList -Option $mixedOptions |
                Should -Be @('Windows', 'macOS')
        }
    }

    It 'Should convert selected option objects without a typed-selection round trip' {
        InModuleScope IntuneHydrationKit {
            $operationOption = Get-HydrationTuiOperationOption | Where-Object { $_.Number -eq 2 }
            $importOptions = @(Get-HydrationTuiImportOption | Where-Object { $_.Number -in @(1, 3, 11) })
            $platformOptions = @(Get-HydrationTuiPlatformOption | Where-Object { $_.Number -in @(1, 2) })

            $operation = $operationOption.Options
            $imports = ConvertTo-HydrationTuiImportMap -Option $importOptions
            $platforms = ConvertTo-HydrationTuiPlatformList -Option $platformOptions

            $operation.dryRun | Should -BeTrue
            $imports.dynamicGroups | Should -BeTrue
            $imports.deviceFilters | Should -BeTrue
            $imports.mobileApps | Should -BeTrue
            $platforms | Should -Be @('Windows', 'macOS')
        }
    }

    It 'Should resolve typed option selections once before conversion' {
        InModuleScope IntuneHydrationKit {
            $options = @(Get-HydrationTuiPlatformOption)

            $selected = @(Resolve-HydrationTuiOptionSelection -Options $options -Selection 'all, 1, 1' -AllowAllKeyword)

            $selected.Number | Should -Be @(0, 1)
            $selected.Value | Should -Be @('All', 'Windows')
        }
    }

    It 'Should resolve TUI selections to settings compatible with the existing execution path' {
        InModuleScope IntuneHydrationKit {
            $settings = & $script:ResolveTestHydrationTuiSelection -Selection (& $script:NewTestHydrationTuiSelection -OperationNumber 2 -ImportNumber 3 -Platforms @('Windows') -Environment 'USGov' -VerboseEnabled $true)

            $settings.tenant.tenantId | Should -BeNullOrEmpty
            $settings.authentication.mode | Should -Be 'interactive'
            $settings.authentication.environment | Should -Be 'USGov'
            $settings.options.create | Should -BeTrue
            $settings.options.delete | Should -BeFalse
            $settings.options.dryRun | Should -BeTrue
            $settings.options.verbose | Should -BeTrue
            $settings.options.forceConsent | Should -BeFalse
            $settings.imports.deviceFilters | Should -BeTrue
            $settings.platforms | Should -Be @('Windows')
            $settings.reporting.formats | Should -Be @('markdown')
            $settings.mobileApps.remediation.enabled | Should -BeTrue
        }
    }

    It 'Should include common WhatIf and Verbose settings in TUI-resolved settings' {
        InModuleScope IntuneHydrationKit {
            $settings = & $script:ResolveTestHydrationTuiSelection -Selection (& $script:NewTestHydrationTuiSelection -OperationNumber 1) -WhatIfEnabled $true -CommonVerboseEnabled $true

            $settings.options.dryRun | Should -BeTrue
            $settings.options.verbose | Should -BeTrue
        }
    }

    It 'Should resolve TUI consent prompt selection to execution options' {
        InModuleScope IntuneHydrationKit {
            $settings = & $script:ResolveTestHydrationTuiSelection -Selection (& $script:NewTestHydrationTuiSelection -ConsentPromptEnabled $true)

            $settings.options.forceConsent | Should -BeTrue
        }
    }

    It 'Should detect cancel input values' {
        InModuleScope IntuneHydrationKit {
            Test-HydrationTuiCancelValue -Value 'q' | Should -BeTrue
            Test-HydrationTuiCancelValue -Value 'cancel' | Should -BeTrue
            Test-HydrationTuiCancelValue -Value 'anything else' | Should -BeFalse
        }
    }

    It 'Should map typed multi-select shortcut keys by character' {
        InModuleScope IntuneHydrationKit {
            $lowerA = [System.ConsoleKeyInfo]::new([char]'a', [System.ConsoleKey]::A, $false, $false, $false)
            $upperA = [System.ConsoleKeyInfo]::new([char]'A', [System.ConsoleKey]::A, $true, $false, $false)
            $lowerQ = [System.ConsoleKeyInfo]::new([char]'q', [System.ConsoleKey]::Q, $false, $false, $false)
            $space = [System.ConsoleKeyInfo]::new([char]' ', [System.ConsoleKey]::Spacebar, $false, $false, $false)

            Get-HydrationTuiKeyAction -KeyInfo $lowerA | Should -Be 'SelectAll'
            Get-HydrationTuiKeyAction -KeyInfo $upperA | Should -Be 'SelectAll'
            Get-HydrationTuiKeyAction -KeyInfo $lowerQ | Should -Be 'Cancel'
            Get-HydrationTuiKeyAction -KeyInfo $space | Should -Be 'Toggle'
        }
    }

    It 'Should update multi-select navigation and terminal state without console input' {
        InModuleScope IntuneHydrationKit {
            $checked = [bool[]]@($false, $true, $false)

            $movedUp = Update-HydrationTuiMultiSelectState -SelectedIndex 0 -Checked $checked -Action 'MoveUp'
            $movedDown = Update-HydrationTuiMultiSelectState -SelectedIndex 2 -Checked $checked -Action 'MoveDown'
            $confirmed = Update-HydrationTuiMultiSelectState -SelectedIndex 1 -Checked $checked -Action 'Confirm'
            $cancelled = Update-HydrationTuiMultiSelectState -SelectedIndex 1 -Checked $checked -Action 'Cancel'

            $movedUp.SelectedIndex | Should -Be 2
            $movedDown.SelectedIndex | Should -Be 0
            $confirmed.Confirmed | Should -BeTrue
            $confirmed.Cancelled | Should -BeFalse
            $cancelled.Cancelled | Should -BeTrue
        }
    }

    It 'Should not confirm multi-select menus when no item is checked' {
        InModuleScope IntuneHydrationKit {
            $checked = [bool[]]@($false, $false, $false)

            $state = Update-HydrationTuiMultiSelectState -SelectedIndex 1 -Checked $checked -Action 'Confirm'

            $state.Confirmed | Should -BeFalse
            $state.Cancelled | Should -BeFalse
            $state.Checked | Should -Be @($false, $false, $false)
        }
    }

    It 'Should toggle all items with SelectAll in normal multi-select menus' {
        InModuleScope IntuneHydrationKit {
            $partiallyChecked = [bool[]]@($true, $false, $false)
            $allChecked = [bool[]]@($true, $true, $true)

            $selectedAll = Update-HydrationTuiMultiSelectState -SelectedIndex 1 -Checked $partiallyChecked -Action 'SelectAll'
            $selectedNone = Update-HydrationTuiMultiSelectState -SelectedIndex 1 -Checked $allChecked -Action 'SelectAll'

            $selectedAll.Checked | Should -Be @($true, $true, $true)
            $selectedNone.Checked | Should -Be @($false, $false, $false)
            $partiallyChecked | Should -Be @($true, $false, $false)
        }
    }

    It 'Should select only All with SelectAll in exclusive-first multi-select menus' {
        InModuleScope IntuneHydrationKit {
            $checked = [bool[]]@($false, $true, $true)

            $state = Update-HydrationTuiMultiSelectState `
                -SelectedIndex 2 `
                -Checked $checked `
                -Action 'SelectAll' `
                -ExclusiveFirst

            $state.Checked | Should -Be @($true, $false, $false)
            $checked | Should -Be @($false, $true, $true)
        }
    }

    It 'Should keep exclusive-first selections mutually exclusive when toggling' {
        InModuleScope IntuneHydrationKit {
            $allSelected = [bool[]]@($true, $false, $false)
            $specificSelected = [bool[]]@($false, $true, $true)

            $specificState = Update-HydrationTuiMultiSelectState `
                -SelectedIndex 2 `
                -Checked $allSelected `
                -Action 'Toggle' `
                -ExclusiveFirst
            $allState = Update-HydrationTuiMultiSelectState `
                -SelectedIndex 0 `
                -Checked $specificSelected `
                -Action 'Toggle' `
                -ExclusiveFirst

            $specificState.Checked | Should -Be @($false, $false, $true)
            $allState.Checked | Should -Be @($true, $false, $false)
        }
    }

    It 'Should use arrow single-select results for operation mapping' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $true } -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiSelect {
                [pscustomobject]@{
                    Cancelled = $false
                    Indices   = @(1)
                }
            } -ModuleName IntuneHydrationKit

            $operation = Read-HydrationTuiOperation

            $operation.create | Should -BeTrue
            $operation.delete | Should -BeFalse
            $operation.dryRun | Should -BeTrue
        }
    }

    It 'Should use arrow multi-select results for import mapping' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $true } -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiSelect {
                [pscustomobject]@{
                    Cancelled = $false
                    Indices   = @(0, 2, 10)
                }
            } -ModuleName IntuneHydrationKit

            $imports = Read-HydrationTuiImport

            $imports.dynamicGroups | Should -BeTrue
            $imports.deviceFilters | Should -BeTrue
            $imports.mobileApps | Should -BeTrue
        }
    }

    It 'Should require an explicit arrow platform selection before continuing' {
        InModuleScope IntuneHydrationKit {
            $script:platformSelectionCallCount = 0
            Mock Test-HydrationTuiArrowKeySupport { $true } -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiSelect {
                $script:platformSelectionCallCount++
                if ($script:platformSelectionCallCount -eq 1) {
                    return [pscustomobject]@{
                        Cancelled = $false
                        Indices   = @()
                    }
                }

                [pscustomobject]@{
                    Cancelled = $false
                    Indices   = @(0)
                }
            } -ModuleName IntuneHydrationKit

            Read-HydrationTuiPlatform | Should -Be @('All')
            Should -Invoke Show-HydrationTuiSelect -ModuleName IntuneHydrationKit -Times 2 -Exactly
        }
    }

    It 'Should keep number prompt fallback when arrow menus are unavailable' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $false } -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiHeader -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiPanel -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiInput {
                [pscustomobject]@{
                    Cancelled = $false
                    Value     = '3'
                }
            } -ModuleName IntuneHydrationKit

            $operation = Read-HydrationTuiOperation

            $operation.create | Should -BeFalse
            $operation.delete | Should -BeTrue
            $operation.dryRun | Should -BeFalse
            Should -Invoke Show-HydrationTuiHeader -ModuleName IntuneHydrationKit -Times 1 -Exactly
        }
    }

    It 'Should show the branded header on the review screen' {
        InModuleScope IntuneHydrationKit {
            Mock Clear-HydrationTuiScreen -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiHeader -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiPanel -ModuleName IntuneHydrationKit

            $settings = & $script:ResolveTestHydrationTuiSelection -Selection (& $script:NewTestHydrationTuiSelection -OperationNumber 1)

            Show-HydrationTuiReview -Settings $settings

            Should -Invoke Clear-HydrationTuiScreen -ModuleName IntuneHydrationKit -Times 1 -Exactly
            Should -Invoke Show-HydrationTuiHeader -ModuleName IntuneHydrationKit -Times 1 -Exactly
            Should -Invoke Show-HydrationTuiPanel -ModuleName IntuneHydrationKit -Times 1 -Exactly
        }
    }

    It 'Should show WhatIf delete as dry-run delete on the review screen' {
        InModuleScope IntuneHydrationKit {
            Mock Clear-HydrationTuiScreen -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiHeader -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiPanel -ModuleName IntuneHydrationKit

            Show-HydrationTuiReview -Settings @{
                tenant    = @{ tenantId = '12345678-1234-1234-1234-123456789abc' }
                options   = @{ create = $false; delete = $true; dryRun = $true; verbose = $false }
                imports   = @{ deviceFilters = $true }
                platforms = @('All')
            }

            Should -Invoke Show-HydrationTuiPanel -ModuleName IntuneHydrationKit -Times 1 -Exactly -ParameterFilter {
                $Lines -contains 'Operation: Dry-run delete'
            }
        }
    }

    It 'Should clear and redraw the TUI header before confirmation prompts by default' {
        InModuleScope IntuneHydrationKit {
            Mock Clear-HydrationTuiScreen -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiHeader -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiInput {
                [pscustomobject]@{
                    Cancelled = $false
                    Value     = 'y'
                }
            } -ModuleName IntuneHydrationKit

            Confirm-HydrationTuiChoice -Prompt 'Enable verbose logging?' -Default:$false | Should -BeTrue

            Should -Invoke Clear-HydrationTuiScreen -ModuleName IntuneHydrationKit -Times 1 -Exactly
            Should -Invoke Show-HydrationTuiHeader -ModuleName IntuneHydrationKit -Times 1 -Exactly
            Should -Invoke Read-HydrationTuiInput -ModuleName IntuneHydrationKit -Times 1 -Exactly -ParameterFilter {
                $Prompt -eq 'Enable verbose logging? [y/N]'
            }
        }
    }

    It 'Should keep the current screen for confirmations that opt out of clearing' {
        InModuleScope IntuneHydrationKit {
            Mock Clear-HydrationTuiScreen -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiHeader -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiInput {
                [pscustomobject]@{
                    Cancelled = $false
                    Value     = 'n'
                }
            } -ModuleName IntuneHydrationKit

            Confirm-HydrationTuiChoice -Prompt 'Run hydration with these settings?' -Default:$false -ClearScreen:$false | Should -BeFalse

            Should -Invoke Clear-HydrationTuiScreen -ModuleName IntuneHydrationKit -Times 0
            Should -Invoke Show-HydrationTuiHeader -ModuleName IntuneHydrationKit -Times 0
            Should -Invoke Read-HydrationTuiInput -ModuleName IntuneHydrationKit -Times 1 -Exactly -ParameterFilter {
                $Prompt -eq 'Run hydration with these settings? [y/N]'
            }
        }
    }

    It 'Should include the website and attribution in the branded header' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $false } -ModuleName IntuneHydrationKit

            $writer = [System.IO.StringWriter]::new()
            $originalOutput = [Console]::Out
            try {
                [Console]::SetOut($writer)
                Show-HydrationTuiHeader
            } finally {
                [Console]::SetOut($originalOutput)
            }

            $output = $writer.ToString()
            $output | Should -Match 'IntuneHydrationKit\.com'
            $output | Should -Match 'Made By Jorgeasaurus'
        }
    }

    It 'Should match the normal info output blue for TUI text' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $true } -ModuleName IntuneHydrationKit

            $palette = Get-HydrationTuiPalette
            $infoBlue = "$($PSStyle.Foreground.BrightCyan)"

            $palette.Text | Should -Be $infoBlue
            $palette.Accent | Should -Be $infoBlue
            $palette.Highlight | Should -Match ([regex]::Escape($infoBlue))
        }
    }

    It 'Should render gradient strings when arrow-key TUI styling is available' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $true } -ModuleName IntuneHydrationKit

            $gradient = Get-HydrationTuiGradientString -Text 'IHD'

            $gradient | Should -Match ([regex]::Escape("$([char]0x1B)[38;2;"))
            $gradient | Should -Match 'I'
            $gradient | Should -Match 'D'
        }
    }

    It 'Should use a dark blue gradient start point' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $true } -ModuleName IntuneHydrationKit

            $gradient = Get-HydrationTuiGradientString -Text 'ID'

            $gradient | Should -Match ([regex]::Escape("$([char]0x1B)[38;2;30;64;175mI"))
        }
    }

    It 'Should keep the default gradient in the blue color family' {
        InModuleScope IntuneHydrationKit {
            Mock Test-HydrationTuiArrowKeySupport { $true } -ModuleName IntuneHydrationKit

            $gradient = Get-HydrationTuiGradientString -Text 'ID'

            $gradient | Should -Match ([regex]::Escape("$([char]0x1B)[38;2;56;189;248mD"))
            $gradient | Should -Not -Match '38;2;166;227;161'
        }
    }

    It 'Should keep the TUI workflow selection-only before orchestration review' {
        InModuleScope IntuneHydrationKit {
            Mock Resolve-HydrationExecutionSettings -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiHeader -ModuleName IntuneHydrationKit
            Mock Show-HydrationTuiReview -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiEnvironment { 'Global' } -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiOperation { & $script:NewTestHydrationTuiOperation -Number 2 } -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiImport { & $script:NewTestHydrationTuiImportMap -Number 3 } -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiPlatform { @('Windows') } -ModuleName IntuneHydrationKit
            Mock Confirm-HydrationTuiChoice { $true } -ModuleName IntuneHydrationKit

            $selection = Invoke-HydrationTui

            $selection.ContainsKey('TenantId') | Should -BeFalse
            $selection.Environment | Should -Be 'Global'
            $selection.Operation.dryRun | Should -BeTrue
            $selection.ConsentPromptEnabled | Should -BeTrue
            Should -Invoke Resolve-HydrationExecutionSettings -ModuleName IntuneHydrationKit -Times 0
            Should -Invoke Show-HydrationTuiReview -ModuleName IntuneHydrationKit -Times 0
        }
    }

    It 'Should return only the selection hashtable from the TUI workflow' {
        InModuleScope IntuneHydrationKit {
            Mock Show-HydrationTuiHeader { 'header output' } -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiEnvironment { 'Global' } -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiOperation { & $script:NewTestHydrationTuiOperation -Number 1 } -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiImport { & $script:NewTestHydrationTuiImportMap -Number 3 } -ModuleName IntuneHydrationKit
            Mock Read-HydrationTuiPlatform { @('All') } -ModuleName IntuneHydrationKit
            Mock Confirm-HydrationTuiChoice { $true } -ModuleName IntuneHydrationKit

            $output = @(Invoke-HydrationTui)

            $output.Count | Should -Be 1
            $output[0] | Should -BeOfType [hashtable]
            $output[0].ContainsKey('TenantId') | Should -BeFalse
            $output[0].Operation.create | Should -BeTrue
            $output[0].ConsentPromptEnabled | Should -BeTrue
        }
    }

    It 'Should load bundled TUI ascii art when present' {
        InModuleScope IntuneHydrationKit {
            $art = Get-HydrationTuiAsciiArt

            $art | Should -Not -BeNullOrEmpty
            $art[0].Trim().Length | Should -BeGreaterThan 0
        }
    }
}
