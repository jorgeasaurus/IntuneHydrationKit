#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    # Get reference to the module
    $script:TestModule = Get-Module -Name IntuneHydrationKit

    if (-not $script:TestModule) {
        throw "Failed to import IntuneHydrationKit module"
    }
}

Describe 'Get-OpenIntuneBaseline' {
    Context 'Parameter Validation' {
        It 'Should have RepoUrl parameter with default value' {
            $command = Get-Command Get-OpenIntuneBaseline
            $repoUrlParam = $command.Parameters['RepoUrl']

            $repoUrlParam | Should -Not -BeNullOrEmpty
            $repoUrlParam.ParameterType | Should -Be ([string])
        }

        It 'Should have Branch parameter with default value' {
            $command = Get-Command Get-OpenIntuneBaseline
            $branchParam = $command.Parameters['Branch']

            $branchParam | Should -Not -BeNullOrEmpty
            $branchParam.ParameterType | Should -Be ([string])
        }

        It 'Should have DestinationPath parameter' {
            $command = Get-Command Get-OpenIntuneBaseline
            $destParam = $command.Parameters['DestinationPath']

            $destParam | Should -Not -BeNullOrEmpty
            $destParam.ParameterType | Should -Be ([string])
        }

        It 'Should not require any mandatory parameters' {
            $command = Get-Command Get-OpenIntuneBaseline
            $mandatoryParams = $command.Parameters.Values | Where-Object {
                $_.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }
            }

            $mandatoryParams | Should -BeNullOrEmpty
        }
    }

    Context 'Default Values' {
        It 'Should default RepoUrl to OpenIntuneBaseline GitHub repo' {
            $command = Get-Command Get-OpenIntuneBaseline
            # Check that the function has the expected default in its definition
            $functionDef = (Get-Command Get-OpenIntuneBaseline).ScriptBlock.ToString()
            $functionDef | Should -Match 'https://github.com/SkipToTheEndpoint/OpenIntuneBaseline'
        }

        It 'Should default Branch to main' {
            $functionDef = (Get-Command Get-OpenIntuneBaseline).ScriptBlock.ToString()
            $functionDef | Should -Match '\$Branch\s*=\s*[''"]main[''"]'
        }
    }

    Context 'URL Construction' {
        BeforeAll {
            # Mock Invoke-WebRequest to prevent actual downloads
            Mock Invoke-WebRequest { } -ModuleName IntuneHydrationKit
            Mock Expand-Archive { } -ModuleName IntuneHydrationKit
            Mock Get-ChildItem { } -ModuleName IntuneHydrationKit
            Mock Remove-Item { } -ModuleName IntuneHydrationKit
            Mock Test-Path { $false } -ModuleName IntuneHydrationKit
        }

        It 'Should construct correct zip URL for default repo and branch' {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            try {
                Get-OpenIntuneBaseline -DestinationPath $testPath
            }
            catch {
                # May fail due to mocks, but we want to verify the URL construction
            }

            Should -Invoke Invoke-WebRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -eq 'https://github.com/SkipToTheEndpoint/OpenIntuneBaseline/archive/refs/heads/main.zip'
            }
        }

        It 'Should construct correct zip URL for custom branch' {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            try {
                Get-OpenIntuneBaseline -DestinationPath $testPath -Branch 'develop'
            }
            catch {
                # May fail due to mocks
            }

            Should -Invoke Invoke-WebRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -eq 'https://github.com/SkipToTheEndpoint/OpenIntuneBaseline/archive/refs/heads/develop.zip'
            }
        }

        It 'Should construct correct zip URL for custom repo' {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            try {
                Get-OpenIntuneBaseline -DestinationPath $testPath -RepoUrl 'https://github.com/custom/repo'
            }
            catch {
                # May fail due to mocks
            }

            Should -Invoke Invoke-WebRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Uri -eq 'https://github.com/custom/repo/archive/refs/heads/main.zip'
            }
        }
    }

    Context 'Destination Path Handling' {
        BeforeAll {
            Mock Invoke-WebRequest { } -ModuleName IntuneHydrationKit
            Mock Expand-Archive { } -ModuleName IntuneHydrationKit
            Mock Get-ChildItem { } -ModuleName IntuneHydrationKit
            Mock Remove-Item { } -ModuleName IntuneHydrationKit
            Mock Move-Item { } -ModuleName IntuneHydrationKit
            Mock Test-Path { $false } -ModuleName IntuneHydrationKit
        }

        It 'Should use temp directory when DestinationPath not specified' {
            $functionDef = (Get-Command Get-OpenIntuneBaseline).ScriptBlock.ToString()
            $functionDef | Should -Match 'GetTempPath'
            $functionDef | Should -Match 'OpenIntuneBaseline'
        }

        It 'Should return the destination path on success' {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            $result = Get-OpenIntuneBaseline -DestinationPath $testPath

            $result | Should -Be $testPath
        }

        It 'Should clean existing directory before extraction' {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            # Mock Test-Path to return true for destination path
            Mock Test-Path { $true } -ModuleName IntuneHydrationKit -ParameterFilter { $Path -eq $testPath }

            Get-OpenIntuneBaseline -DestinationPath $testPath

            Should -Invoke Remove-Item -ModuleName IntuneHydrationKit -ParameterFilter {
                $Path -eq $testPath -and $Recurse -eq $true -and $Force -eq $true
            }
        }
    }

    Context 'Archive Extraction' {
        BeforeAll {
            Mock Invoke-WebRequest { } -ModuleName IntuneHydrationKit
            Mock Remove-Item { } -ModuleName IntuneHydrationKit
            Mock Move-Item { } -ModuleName IntuneHydrationKit
            Mock Test-Path { $false } -ModuleName IntuneHydrationKit
        }

        It 'Should call Expand-Archive with Force parameter' {
            Mock Expand-Archive { } -ModuleName IntuneHydrationKit
            Mock Get-ChildItem { } -ModuleName IntuneHydrationKit

            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            Get-OpenIntuneBaseline -DestinationPath $testPath

            Should -Invoke Expand-Archive -ModuleName IntuneHydrationKit -ParameterFilter {
                $Force -eq $true
            }
        }

        It 'Should extract to the specified destination path' {
            Mock Expand-Archive { } -ModuleName IntuneHydrationKit
            Mock Get-ChildItem { } -ModuleName IntuneHydrationKit

            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            Get-OpenIntuneBaseline -DestinationPath $testPath

            Should -Invoke Expand-Archive -ModuleName IntuneHydrationKit -ParameterFilter {
                $DestinationPath -eq $testPath
            }
        }
    }

    Context 'Subfolder Handling' {
        BeforeAll {
            Mock Invoke-WebRequest { } -ModuleName IntuneHydrationKit
            Mock Expand-Archive { } -ModuleName IntuneHydrationKit
            Mock Test-Path { $false } -ModuleName IntuneHydrationKit
        }

        It 'Should move extracted subfolder contents up one level' {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            # Mock Get-ChildItem to return a fake extracted folder
            $mockFolder = [PSCustomObject]@{
                FullName = "$testPath\OpenIntuneBaseline-main"
                Name     = 'OpenIntuneBaseline-main'
            }
            Mock Get-ChildItem { $mockFolder } -ModuleName IntuneHydrationKit -ParameterFilter { $Directory }
            Mock Move-Item { } -ModuleName IntuneHydrationKit
            Mock Remove-Item { } -ModuleName IntuneHydrationKit

            Get-OpenIntuneBaseline -DestinationPath $testPath

            # Should move the extracted folder to temp location
            Should -Invoke Move-Item -ModuleName IntuneHydrationKit -Times 2 -Scope It
        }
    }

    Context 'Cleanup' {
        BeforeAll {
            Mock Invoke-WebRequest { } -ModuleName IntuneHydrationKit
            Mock Expand-Archive { } -ModuleName IntuneHydrationKit
            Mock Get-ChildItem { } -ModuleName IntuneHydrationKit
            Mock Move-Item { } -ModuleName IntuneHydrationKit
            Mock Test-Path { $false } -ModuleName IntuneHydrationKit
        }

        It 'Should clean up downloaded zip file after extraction' {
            Mock Remove-Item { } -ModuleName IntuneHydrationKit

            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            Get-OpenIntuneBaseline -DestinationPath $testPath

            Should -Invoke Remove-Item -ModuleName IntuneHydrationKit -ParameterFilter {
                $Path -like '*OpenIntuneBaseline*.zip'
            }
        }
    }

    Context 'Error Handling' {
        It 'Should throw when download fails' {
            Mock Invoke-WebRequest { throw 'Download failed' } -ModuleName IntuneHydrationKit

            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            { Get-OpenIntuneBaseline -DestinationPath $testPath } | Should -Throw
        }

        It 'Should throw when extraction fails' {
            Mock Invoke-WebRequest { } -ModuleName IntuneHydrationKit
            Mock Expand-Archive { throw 'Extraction failed' } -ModuleName IntuneHydrationKit
            Mock Test-Path { $false } -ModuleName IntuneHydrationKit

            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            { Get-OpenIntuneBaseline -DestinationPath $testPath } | Should -Throw
        }

        It 'Should include error details in thrown exception' {
            Mock Invoke-WebRequest { throw 'Network timeout' } -ModuleName IntuneHydrationKit

            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "OIB-Test-$(Get-Random)"

            { Get-OpenIntuneBaseline -DestinationPath $testPath } | Should -Throw -ExpectedMessage '*Network timeout*'
        }
    }

    Context 'WhatIf Behavior' {
        BeforeAll {
            Mock Invoke-WebRequest { } -ModuleName IntuneHydrationKit
            Mock Expand-Archive { } -ModuleName IntuneHydrationKit
            Mock Get-ChildItem { } -ModuleName IntuneHydrationKit
            Mock Move-Item { } -ModuleName IntuneHydrationKit
            Mock Test-Path { $true } -ModuleName IntuneHydrationKit
        }

        It 'Should execute Remove-Item regardless of WhatIf preference' {
            # The function explicitly uses -WhatIf:$false to ensure cleanup happens
            $functionDef = (Get-Command Get-OpenIntuneBaseline).ScriptBlock.ToString()
            $functionDef | Should -Match 'Remove-Item.*-WhatIf:\$false'
        }

        It 'Should execute Expand-Archive regardless of WhatIf preference' {
            $functionDef = (Get-Command Get-OpenIntuneBaseline).ScriptBlock.ToString()
            $functionDef | Should -Match 'Expand-Archive.*-WhatIf:\$false'
        }

        It 'Should execute Move-Item regardless of WhatIf preference' {
            $functionDef = (Get-Command Get-OpenIntuneBaseline).ScriptBlock.ToString()
            $functionDef | Should -Match 'Move-Item.*-WhatIf:\$false'
        }
    }
}
