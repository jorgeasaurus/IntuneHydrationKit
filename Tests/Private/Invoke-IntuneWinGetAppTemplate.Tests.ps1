#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Invoke-IntuneWinGetAppTemplate' {
    BeforeAll {
        $script:testWorkingRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/Invoke-IntuneWinGetAppTemplate'
        if (Test-Path -Path $script:testWorkingRoot) {
            Remove-Item -Path $script:testWorkingRoot -Recurse -Force
        }

        $null = New-Item -Path $script:testWorkingRoot -ItemType Directory -Force
    }

    Context 'packageIdentifier validation' {
        It 'throws terminating error when packageIdentifier is missing' {
            InModuleScope IntuneHydrationKit -Parameters @{ WorkingRoot = $script:testWorkingRoot } {
                param($WorkingRoot)

                $template = [pscustomobject]@{
                    templateId = 'test-app'
                }

                { Invoke-IntuneWinGetAppTemplate -Template $template -DisplayName 'Test App' -WorkingDirectory $WorkingRoot } |
                    Should -Throw '*missing or blank packageIdentifier*'
            }
        }

        It 'throws terminating error when packageIdentifier is blank' {
            InModuleScope IntuneHydrationKit -Parameters @{ WorkingRoot = $script:testWorkingRoot } {
                param($WorkingRoot)

                $template = [pscustomobject]@{
                    templateId        = 'test-app'
                    packageIdentifier = ''
                }

                { Invoke-IntuneWinGetAppTemplate -Template $template -DisplayName 'Test App' -WorkingDirectory $WorkingRoot } |
                    Should -Throw '*missing or blank packageIdentifier*'
            }
        }

        It 'throws terminating error when packageIdentifier is whitespace-only' {
            InModuleScope IntuneHydrationKit -Parameters @{ WorkingRoot = $script:testWorkingRoot } {
                param($WorkingRoot)

                $template = [pscustomobject]@{
                    templateId        = 'test-app'
                    packageIdentifier = '   '
                }

                { Invoke-IntuneWinGetAppTemplate -Template $template -DisplayName 'Test App' -WorkingDirectory $WorkingRoot } |
                    Should -Throw '*missing or blank packageIdentifier*'
            }
        }

        It 'does not throw when packageIdentifier is valid' {
            InModuleScope IntuneHydrationKit -Parameters @{ WorkingRoot = $script:testWorkingRoot } {
                param($WorkingRoot)

                Mock New-WinGetWrapperFiles {
                    [pscustomobject]@{
                        InstallScriptPath   = Join-Path $WorkingRoot 'content\Install-WinGetPackage.ps1'
                        UninstallScriptPath = Join-Path $WorkingRoot 'content\Uninstall-WinGetPackage.ps1'
                    }
                } -ParameterFilter { $Path -and $Template }

                Mock New-IntuneWinPackagingContext { } -ParameterFilter { $SourcePath -and $OutputPath }
                Mock New-IntuneWinPackage { } -ParameterFilter { $PackagingContext }
                Mock New-WinGetOwnershipNotes { '' }
                Mock Get-WinGetDetectionRules { @() }
                Mock Get-PrimaryArchitecture { 'x64' }
                Mock Get-RequirementArchitecture { 'x64' }
                Mock New-IntuneWin32AppPayload { [pscustomobject]@{ appVersion = '1.0.0' } }
                Mock Invoke-HydrationGraphRequest { [pscustomobject]@{ id = '00000000-0000-0000-0000-000000000001' } }
                Mock Publish-IntuneWin32AppContent { [pscustomobject]@{ ContentVersionId = '1' } }
                Mock Write-HydrationLog { }

                $template = [pscustomobject]@{
                    templateId        = 'test-app'
                    packageIdentifier = 'Test.App'
                    publisher         = 'Test Publisher'
                    description       = 'Test app description'
                    TemplatePath      = Join-Path $WorkingRoot 'test-app.json'
                    resolvedPackage   = [pscustomobject]@{
                        packageVersion    = '1.0.0'
                        manifestSource    = [pscustomobject]@{
                            repository  = 'microsoft/winget-pkgs'
                            ref         = 'master'
                            packagePath = 'manifests/t/Test/App'
                            versionPath = 'manifests/t/Test/App/1.0.0'
                        }
                        selectedInstaller = [pscustomobject]@{
                            Architecture    = 'x64'
                            Scope           = 'machine'
                            InstallerLocale = 'en-US'
                            InstallerType   = 'exe'
                            InstallerUrl    = 'https://example.test/app.exe'
                        }
                    }
                    package           = [pscustomobject]@{
                        match = [pscustomobject]@{
                            architectures = @('x64')
                            scope         = 'machine'
                            locale        = 'en-US'
                        }
                    }
                    install           = [pscustomobject]@{
                        experience      = 'system'
                        restartBehavior = 'suppress'
                    }
                    uninstall         = [pscustomobject]@{
                        behavior = 'allow'
                    }
                    requirements      = [pscustomobject]@{
                        minimumSupportedWindowsRelease = 'W10_22H2'
                        architectures                  = @('x64')
                        minimumFreeDiskSpaceInMB       = 1024
                        minimumMemoryInMB              = 2048
                    }
                    metadata          = [pscustomobject]@{
                        placeholders = [pscustomobject]@{
                            owner       = 'Test Owner'
                            scopeTagIds = @('1')
                        }
                    }
                    icon              = [pscustomobject]@{
                        sourceType = 'none'
                        fileName   = $null
                    }
                }

                { Invoke-IntuneWinGetAppTemplate -Template $template -DisplayName 'Test App' -WorkingDirectory $WorkingRoot } |
                    Should -Not -Throw
            }
        }

        It 'returns a failed result when a template lacks bundled resolvedPackage metadata' {
            InModuleScope IntuneHydrationKit -Parameters @{ WorkingRoot = $script:testWorkingRoot } {
                param($WorkingRoot)

                $template = [pscustomobject]@{
                    templateId        = 'test-app'
                    packageIdentifier = 'Test.App'
                }

                $result = Invoke-IntuneWinGetAppTemplate -Template $template -DisplayName 'Test App' -WorkingDirectory $WorkingRoot

                $result.Action | Should -Be 'Failed'
                $result.Status | Should -BeLike '*Open an issue requesting this app or submit a PR*'
            }
        }

        It 'uses resolved template metadata instead of live GitHub manifest resolution' {
            InModuleScope IntuneHydrationKit -Parameters @{ WorkingRoot = $script:testWorkingRoot } {
                param($WorkingRoot)

                Mock New-WinGetWrapperFiles {
                    [pscustomobject]@{
                        InstallScriptPath   = Join-Path $WorkingRoot 'content\Install-WinGetPackage.ps1'
                        UninstallScriptPath = Join-Path $WorkingRoot 'content\Uninstall-WinGetPackage.ps1'
                    }
                } -ParameterFilter { $Path -and $Template }
                Mock New-IntuneWinPackagingContext { } -ParameterFilter { $PackageMetadata.PackageVersion -eq 'latest' }
                Mock New-IntuneWinPackage { } -ParameterFilter { $PackagingContext }
                Mock New-WinGetOwnershipNotes { '' }
                Mock Get-WinGetDetectionRules { @() }
                Mock Get-RequirementArchitecture { 'x64' }
                Mock New-IntuneWin32AppPayload { [pscustomobject]@{ appVersion = 'latest' } }
                Mock Invoke-HydrationGraphRequest { [pscustomobject]@{ id = '00000000-0000-0000-0000-000000000001' } }
                Mock Publish-IntuneWin32AppContent { [pscustomobject]@{ ContentVersionId = '1' } }
                Mock Write-HydrationLog { }

                $template = [pscustomobject]@{
                    templateId        = 'test-app'
                    packageIdentifier = 'Test.App'
                    displayName       = 'Test App'
                    publisher         = 'Test Publisher'
                    description       = 'Test app description'
                    TemplatePath      = Join-Path $WorkingRoot 'test-app.json'
                    package           = [pscustomobject]@{
                        match = [pscustomobject]@{
                            architectures  = @('x64')
                            installerTypes = @('exe')
                            scope          = 'machine'
                            locale         = 'en-US'
                        }
                    }
                    resolvedPackage   = [pscustomobject]@{
                        packageVersion    = 'latest'
                        manifestSource    = [pscustomobject]@{
                            repository  = 'microsoft/winget-pkgs'
                            ref         = 'master'
                            packagePath = 'manifests/t/Test/App'
                            versionPath = 'manifests/t/Test/App'
                        }
                        selectedInstaller = [pscustomobject]@{
                            Architecture         = 'x64'
                            Scope                = 'machine'
                            InstallerLocale      = 'en-US'
                            InstallerType        = 'exe'
                            InstallerUrl         = $null
                            InstallerSha256      = $null
                            ProductCode          = $null
                            PackageFamilyName    = $null
                            NestedInstallerType  = $null
                            AppsAndFeaturesEntry = @()
                        }
                    }
                    install           = [pscustomobject]@{
                        experience      = 'system'
                        restartBehavior = 'suppress'
                    }
                    uninstall         = [pscustomobject]@{
                        behavior = 'allow'
                    }
                    requirements      = [pscustomobject]@{
                        minimumSupportedWindowsRelease = 'W10_22H2'
                        architectures                  = @('x64')
                    }
                    metadata          = [pscustomobject]@{
                        placeholders = [pscustomobject]@{
                            owner       = ''
                            scopeTagIds = @()
                        }
                    }
                    icon              = [pscustomobject]@{
                        sourceType = 'none'
                        fileName   = $null
                    }
                }

                { Invoke-IntuneWinGetAppTemplate -Template $template -DisplayName 'Test App' -WorkingDirectory $WorkingRoot } |
                    Should -Not -Throw
            }
        }

        It 'fails fast when resolved template metadata is missing core nodes' {
            InModuleScope IntuneHydrationKit {
                $template = [pscustomobject]@{
                    templateId        = 'test-app'
                    packageIdentifier = 'Test.App'
                    displayName       = 'Test App'
                    publisher         = 'Test Publisher'
                    description       = 'Test app description'
                    package           = [pscustomobject]@{
                        match = [pscustomobject]@{
                            locale = 'en-US'
                        }
                    }
                    resolvedPackage   = [pscustomobject]@{
                        packageVersion = 'latest'
                        manifestSource = [pscustomobject]@{
                            repository  = 'microsoft/winget-pkgs'
                            ref         = 'master'
                            packagePath = 'manifests/t/Test/App'
                            versionPath = 'manifests/t/Test/App'
                            installerFile = $null
                            localeFile    = $null
                        }
                    }
                }

                { New-WinGetPackageMetadataFromTemplate -Template $template } |
                    Should -Throw '*resolvedPackage metadata is incomplete*'
            }
        }
    }
}
