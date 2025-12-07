#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    # Create temp directory for test files
    $script:TestTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PesterTests-$(Get-Random)"
    New-Item -Path $script:TestTempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup temp directory
    if (Test-Path $script:TestTempDir) {
        Remove-Item -Path $script:TestTempDir -Recurse -Force
    }
}

Describe 'Import-HydrationSettings' {
    Context 'Parameter Validation' {
        It 'Should have Path parameter mandatory' {
            $command = Get-Command Import-HydrationSettings
            $pathParam = $command.Parameters['Path']

            $mandatoryAttr = $pathParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }

            ($mandatoryAttr | Where-Object { $_.Mandatory }).Count | Should -BeGreaterThan 0
        }

        It 'Should validate that Path exists' {
            $command = Get-Command Import-HydrationSettings
            $pathParam = $command.Parameters['Path']

            $validateScript = $pathParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateScriptAttribute] }
            $validateScript | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Loading Settings from File' {
        BeforeEach {
            # Mock Write-HydrationLog to suppress output
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should load valid settings file' {
            $settingsContent = @{
                tenant         = @{
                    tenantId   = '12345678-1234-1234-1234-123456789abc'
                    tenantName = 'test.onmicrosoft.com'
                }
                authentication = @{
                    mode = 'interactive'
                }
                options        = @{
                    create = $true
                }
            }

            $settingsPath = Join-Path $script:TestTempDir 'valid-settings.json'
            $settingsContent | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath

            $result = Import-HydrationSettings -Path $settingsPath

            $result | Should -Not -BeNullOrEmpty
            $result.tenant.tenantId | Should -Be '12345678-1234-1234-1234-123456789abc'
        }

        It 'Should preserve all settings properties' {
            $settingsContent = @{
                tenant         = @{
                    tenantId   = '12345678-1234-1234-1234-123456789abc'
                    tenantName = 'test.onmicrosoft.com'
                }
                authentication = @{
                    mode        = 'clientSecret'
                    clientId    = 'app-id'
                    environment = 'USGov'
                }
                options        = @{
                    create  = $true
                    delete  = $false
                    dryRun  = $true
                    verbose = $false
                }
                imports        = @{
                    dynamicGroups     = $true
                    conditionalAccess = $false
                }
            }

            $settingsPath = Join-Path $script:TestTempDir 'full-settings.json'
            $settingsContent | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath

            $result = Import-HydrationSettings -Path $settingsPath

            $result.authentication.mode | Should -Be 'clientSecret'
            $result.authentication.environment | Should -Be 'USGov'
            $result.options.dryRun | Should -Be $true
            $result.imports.dynamicGroups | Should -Be $true
            $result.imports.conditionalAccess | Should -Be $false
        }

        It 'Should throw when tenantId is missing' {
            $settingsContent = @{
                tenant         = @{
                    tenantName = 'test.onmicrosoft.com'
                }
                authentication = @{
                    mode = 'interactive'
                }
            }

            $settingsPath = Join-Path $script:TestTempDir 'missing-tenant.json'
            $settingsContent | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath

            { Import-HydrationSettings -Path $settingsPath } | Should -Throw '*tenantId*'
        }

        It 'Should throw for invalid JSON' {
            $settingsPath = Join-Path $script:TestTempDir 'invalid.json'
            'not valid json {{{' | Set-Content -Path $settingsPath

            { Import-HydrationSettings -Path $settingsPath } | Should -Throw
        }

        It 'Should throw for non-existent file' {
            { Import-HydrationSettings -Path 'C:\nonexistent\file.json' } | Should -Throw
        }

        It 'Should handle UTF-8 encoded files' {
            $settingsContent = @{
                tenant         = @{
                    tenantId   = '12345678-1234-1234-1234-123456789abc'
                    tenantName = 'test-unicode-\u00e9.onmicrosoft.com'
                }
                authentication = @{
                    mode = 'interactive'
                }
            }

            $settingsPath = Join-Path $script:TestTempDir 'utf8-settings.json'
            $settingsContent | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding utf8

            $result = Import-HydrationSettings -Path $settingsPath

            $result | Should -Not -BeNullOrEmpty
        }
    }
    Context 'Return Type' {
        It 'Should return hashtable from file' {
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit

            $settingsContent = @{
                tenant         = @{
                    tenantId = '12345678-1234-1234-1234-123456789abc'
                }
                authentication = @{
                    mode = 'interactive'
                }
            }

            $settingsPath = Join-Path $script:TestTempDir 'type-test.json'
            $settingsContent | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath

            $result = Import-HydrationSettings -Path $settingsPath

            $result | Should -BeOfType [hashtable]
        }
    }
}
