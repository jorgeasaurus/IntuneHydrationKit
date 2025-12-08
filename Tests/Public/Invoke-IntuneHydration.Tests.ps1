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

    # Create a temp directory for test settings files
    $script:TestTempPath = Join-Path ([System.IO.Path]::GetTempPath()) 'IntuneHydrationKitTests'
    if (-not (Test-Path $script:TestTempPath)) {
        New-Item -Path $script:TestTempPath -ItemType Directory -Force | Out-Null
    }
}

AfterAll {
    # Clean up temp directory
    if (Test-Path $script:TestTempPath) {
        Remove-Item -Path $script:TestTempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-IntuneHydration' {
    Context 'Parameter Validation' {
        It 'Should have SettingsFile parameter set as default' {
            $command = Get-Command Invoke-IntuneHydration
            $command.DefaultParameterSet | Should -Be 'SettingsFile'
        }

        It 'Should have three parameter sets' {
            $command = Get-Command Invoke-IntuneHydration
            $command.ParameterSets.Name | Should -Contain 'SettingsFile'
            $command.ParameterSets.Name | Should -Contain 'Interactive'
            $command.ParameterSets.Name | Should -Contain 'ServicePrincipal'
        }

        It 'Should require SettingsPath in SettingsFile parameter set' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['SettingsPath']

            $settingsFileSet = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'SettingsFile' }

            $settingsFileSet.Mandatory | Should -Be $true
        }

        It 'Should require TenantId in Interactive parameter set' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['TenantId']

            $interactiveSet = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'Interactive' }

            $interactiveSet.Mandatory | Should -Be $true
        }

        It 'Should require TenantId in ServicePrincipal parameter set' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['TenantId']

            $spSet = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'ServicePrincipal' }

            $spSet.Mandatory | Should -Be $true
        }

        It 'Should validate TenantId as GUID format' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['TenantId']

            $validatePattern = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }
            $validatePattern | Should -Not -BeNullOrEmpty
        }

        It 'Should require Interactive switch in Interactive parameter set' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['Interactive']

            $interactiveSet = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'Interactive' }

            $interactiveSet.Mandatory | Should -Be $true
        }

        It 'Should require ClientId in ServicePrincipal parameter set' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['ClientId']

            $spSet = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'ServicePrincipal' }

            $spSet.Mandatory | Should -Be $true
        }

        It 'Should require ClientSecret as SecureString' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['ClientSecret']

            $param.ParameterType | Should -Be ([SecureString])
        }

        It 'Should validate Environment parameter values' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['Environment']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Global'
            $validateSet.ValidValues | Should -Contain 'USGov'
            $validateSet.ValidValues | Should -Contain 'USGovDoD'
            $validateSet.ValidValues | Should -Contain 'Germany'
            $validateSet.ValidValues | Should -Contain 'China'
        }

        It 'Should validate ReportFormats parameter values' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['ReportFormats']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'markdown'
            $validateSet.ValidValues | Should -Contain 'json'
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Invoke-IntuneHydration
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }
    }

    Context 'Target Switch Parameters' {
        It 'Should have All switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['All']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have DynamicGroups switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['DynamicGroups']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have DeviceFilters switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['DeviceFilters']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have OpenIntuneBaseline switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['OpenIntuneBaseline']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have ComplianceTemplates switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['ComplianceTemplates']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have AppProtection switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['AppProtection']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have EnrollmentProfiles switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['EnrollmentProfiles']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have ConditionalAccess switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['ConditionalAccess']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should have NotificationTemplates switch parameter' {
            $command = Get-Command Invoke-IntuneHydration
            $param = $command.Parameters['NotificationTemplates']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Settings File Validation' {
        BeforeAll {
            # Mock all dependent functions to prevent actual execution
            Mock Import-HydrationSettings -ModuleName IntuneHydrationKit
            Mock Connect-IntuneHydration -ModuleName IntuneHydrationKit
            Mock Test-IntunePrerequisites -ModuleName IntuneHydrationKit
            Mock Initialize-HydrationLogging -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678-****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
            Mock Get-ResultSummary { return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0; WouldCreate = 0; WouldUpdate = 0; WouldDelete = 0; Deleted = 0 } } -ModuleName IntuneHydrationKit
        }

        It 'Should reject non-existent settings file path' {
            { Invoke-IntuneHydration -SettingsPath '/nonexistent/path/settings.json' } |
                Should -Throw
        }

        It 'Should call Import-HydrationSettings with correct path' {
            # Create a valid test settings file
            $testSettingsPath = Join-Path $script:TestTempPath 'test-settings.json'
            @{
                tenant = @{ tenantId = '12345678-1234-1234-1234-123456789abc' }
                authentication = @{ mode = 'interactive'; environment = 'Global' }
                options = @{ create = $true; delete = $false }
                imports = @{ dynamicGroups = $true }
                reporting = @{ outputPath = 'Reports'; formats = @('markdown') }
            } | ConvertTo-Json -Depth 10 | Out-File -FilePath $testSettingsPath -Encoding utf8

            Mock Import-HydrationSettings {
                return @{
                    tenant = @{ tenantId = '12345678-1234-1234-1234-123456789abc' }
                    authentication = @{ mode = 'interactive'; environment = 'Global' }
                    options = @{ create = $true; delete = $false }
                    imports = @{ dynamicGroups = $true }
                    reporting = @{ outputPath = 'Reports'; formats = @('markdown') }
                }
            } -ModuleName IntuneHydrationKit

            Invoke-IntuneHydration -SettingsPath $testSettingsPath -WhatIf

            Should -Invoke Import-HydrationSettings -ModuleName IntuneHydrationKit -Times 1
        }
    }

    Context 'Parameter Mode - Target Validation' {
        BeforeAll {
            # Mock all dependent functions
            Mock Connect-IntuneHydration -ModuleName IntuneHydrationKit
            Mock Test-IntunePrerequisites -ModuleName IntuneHydrationKit
            Mock Initialize-HydrationLogging -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678-****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
            Mock Get-ResultSummary { return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0; WouldCreate = 0; WouldUpdate = 0; WouldDelete = 0; Deleted = 0 } } -ModuleName IntuneHydrationKit
        }

        It 'Should throw when no target is specified in parameter mode' {
            { Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create } |
                Should -Throw '*At least one target must be enabled*'
        }

        It 'Should not throw when -All switch is used' {
            Mock Import-IntuneDeviceFilter -ModuleName IntuneHydrationKit
            Mock Import-IntuneBaseline -ModuleName IntuneHydrationKit
            Mock Import-IntuneCompliancePolicy -ModuleName IntuneHydrationKit
            Mock Import-IntuneNotificationTemplate -ModuleName IntuneHydrationKit
            Mock Import-IntuneAppProtectionPolicy -ModuleName IntuneHydrationKit
            Mock Import-IntuneEnrollmentProfile -ModuleName IntuneHydrationKit
            Mock Import-IntuneConditionalAccessPolicy -ModuleName IntuneHydrationKit
            Mock New-IntuneDynamicGroup -ModuleName IntuneHydrationKit
            Mock Get-ChildItem { @() } -ModuleName IntuneHydrationKit

            { Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -All -WhatIf } |
                Should -Not -Throw
        }

        It 'Should not throw when specific target is specified' {
            Mock Import-IntuneDeviceFilter { @() } -ModuleName IntuneHydrationKit

            { Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf } |
                Should -Not -Throw
        }
    }

    Context 'Create/Delete Mode Validation' {
        BeforeAll {
            Mock Connect-IntuneHydration -ModuleName IntuneHydrationKit
            Mock Test-IntunePrerequisites -ModuleName IntuneHydrationKit
            Mock Initialize-HydrationLogging -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678-****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
            Mock Import-IntuneDeviceFilter { @() } -ModuleName IntuneHydrationKit
            Mock Get-ResultSummary { return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0; WouldCreate = 0; WouldUpdate = 0; WouldDelete = 0; Deleted = 0 } } -ModuleName IntuneHydrationKit
        }

        It 'Should throw when both Create and Delete are specified' {
            { Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -Delete -DeviceFilters -WhatIf } |
                Should -Throw "*Only one of 'create' or 'delete'*"
        }

        It 'Should throw when neither Create nor Delete is specified' {
            { Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -DeviceFilters -WhatIf } |
                Should -Throw "*At least one of 'create' or 'delete'*"
        }

        It 'Should not throw when only Create is specified' {
            { Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf } |
                Should -Not -Throw
        }
    }

    Context 'Authentication Flow' {
        BeforeAll {
            Mock Connect-IntuneHydration -ModuleName IntuneHydrationKit
            Mock Test-IntunePrerequisites -ModuleName IntuneHydrationKit
            Mock Initialize-HydrationLogging -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678-****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
            Mock Import-IntuneDeviceFilter { @() } -ModuleName IntuneHydrationKit
            Mock Get-ResultSummary { return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0; WouldCreate = 0; WouldUpdate = 0; WouldDelete = 0; Deleted = 0 } } -ModuleName IntuneHydrationKit
        }

        It 'Should call Connect-IntuneHydration with Interactive parameter' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -ParameterFilter {
                $Interactive -eq $true
            }
        }

        It 'Should call Connect-IntuneHydration with correct TenantId' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -ParameterFilter {
                $TenantId -eq '12345678-1234-1234-1234-123456789abc'
            }
        }

        It 'Should call Connect-IntuneHydration with specified Environment' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -Environment USGov -WhatIf

            Should -Invoke Connect-IntuneHydration -ModuleName IntuneHydrationKit -ParameterFilter {
                $Environment -eq 'USGov'
            }
        }

        It 'Should always call Test-IntunePrerequisites' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            Should -Invoke Test-IntunePrerequisites -ModuleName IntuneHydrationKit -Times 1
        }
    }

    Context 'Return Value' {
        BeforeAll {
            Mock Connect-IntuneHydration -ModuleName IntuneHydrationKit
            Mock Test-IntunePrerequisites -ModuleName IntuneHydrationKit
            Mock Initialize-HydrationLogging -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678-****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
            Mock Import-IntuneDeviceFilter { @() } -ModuleName IntuneHydrationKit
            Mock Get-ResultSummary { return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0; WouldCreate = 0; WouldUpdate = 0; WouldDelete = 0; Deleted = 0 } } -ModuleName IntuneHydrationKit
        }

        It 'Should return object with Success property' {
            $result = Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }

        It 'Should return object with Summary property' {
            $result = Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            $result.Summary | Should -Not -BeNullOrEmpty
        }

        It 'Should return object with Results property' {
            $result = Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            # Results is an array (can be empty) - check hashtable keys
            $result.Keys | Should -Contain 'Results'
        }

        It 'Should return object with ReportPath property' {
            $result = Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            $result.ReportPath | Should -Not -BeNullOrEmpty
        }

        It 'Should return Success = false when there are failures' {
            Mock Get-ResultSummary { return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 1; WouldCreate = 0; WouldUpdate = 0; WouldDelete = 0; Deleted = 0 } } -ModuleName IntuneHydrationKit

            $result = Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            $result.Success | Should -Be $false
        }
    }

    Context 'Import Function Calls' {
        BeforeAll {
            Mock Connect-IntuneHydration -ModuleName IntuneHydrationKit
            Mock Test-IntunePrerequisites -ModuleName IntuneHydrationKit
            Mock Initialize-HydrationLogging -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678-****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
            Mock Get-ResultSummary { return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0; WouldCreate = 0; WouldUpdate = 0; WouldDelete = 0; Deleted = 0 } } -ModuleName IntuneHydrationKit

            # Mock all import functions
            Mock Import-IntuneDeviceFilter { @() } -ModuleName IntuneHydrationKit
            Mock Import-IntuneBaseline { @() } -ModuleName IntuneHydrationKit
            Mock Import-IntuneCompliancePolicy { @() } -ModuleName IntuneHydrationKit
            Mock Import-IntuneNotificationTemplate { @() } -ModuleName IntuneHydrationKit
            Mock Import-IntuneAppProtectionPolicy { @() } -ModuleName IntuneHydrationKit
            Mock Import-IntuneEnrollmentProfile { @() } -ModuleName IntuneHydrationKit
            Mock Import-IntuneConditionalAccessPolicy { @() } -ModuleName IntuneHydrationKit
            Mock New-IntuneDynamicGroup { @{ Action = 'Created'; Id = 'test-id' } } -ModuleName IntuneHydrationKit
        }

        It 'Should call Import-IntuneDeviceFilter when DeviceFilters is enabled' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            Should -Invoke Import-IntuneDeviceFilter -ModuleName IntuneHydrationKit -Times 1
        }

        It 'Should call Import-IntuneCompliancePolicy when ComplianceTemplates is enabled' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -ComplianceTemplates -WhatIf

            Should -Invoke Import-IntuneCompliancePolicy -ModuleName IntuneHydrationKit -Times 1
        }

        It 'Should call Import-IntuneConditionalAccessPolicy when ConditionalAccess is enabled' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -ConditionalAccess -WhatIf

            Should -Invoke Import-IntuneConditionalAccessPolicy -ModuleName IntuneHydrationKit -Times 1
        }

        It 'Should call Import-IntuneEnrollmentProfile when EnrollmentProfiles is enabled' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -EnrollmentProfiles -WhatIf

            Should -Invoke Import-IntuneEnrollmentProfile -ModuleName IntuneHydrationKit -Times 1
        }

        It 'Should call Import-IntuneAppProtectionPolicy when AppProtection is enabled' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -AppProtection -WhatIf

            Should -Invoke Import-IntuneAppProtectionPolicy -ModuleName IntuneHydrationKit -Times 1
        }

        It 'Should call Import-IntuneNotificationTemplate when NotificationTemplates is enabled' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -NotificationTemplates -WhatIf

            Should -Invoke Import-IntuneNotificationTemplate -ModuleName IntuneHydrationKit -Times 1
        }

        It 'Should call all import functions when -All is specified' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -All -WhatIf

            Should -Invoke Import-IntuneDeviceFilter -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneBaseline -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneCompliancePolicy -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneNotificationTemplate -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneAppProtectionPolicy -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneEnrollmentProfile -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneConditionalAccessPolicy -ModuleName IntuneHydrationKit -Times 1
        }

        It 'Should not call import functions for disabled targets' {
            Invoke-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Create -DeviceFilters -WhatIf

            Should -Invoke Import-IntuneDeviceFilter -ModuleName IntuneHydrationKit -Times 1
            Should -Invoke Import-IntuneCompliancePolicy -ModuleName IntuneHydrationKit -Times 0
            Should -Invoke Import-IntuneConditionalAccessPolicy -ModuleName IntuneHydrationKit -Times 0
        }
    }
}
