#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Import-IntuneEnrollmentProfile' {
    BeforeAll {
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit
        Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit
    }

    Context 'Parameter Validation' {
        It 'Should have TemplatePath parameter' {
            $command = Get-Command Import-IntuneEnrollmentProfile
            $param = $command.Parameters['TemplatePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have Platform parameter with ValidateSet' {
            $command = Get-Command Import-IntuneEnrollmentProfile
            $param = $command.Parameters['Platform']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Windows'
            $validateSet.ValidValues | Should -Contain 'macOS'
            $validateSet.ValidValues | Should -Contain 'All'
        }

        It 'Should have DeviceNameTemplate parameter' {
            $command = Get-Command Import-IntuneEnrollmentProfile
            $param = $command.Parameters['DeviceNameTemplate']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Import-IntuneEnrollmentProfile
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneEnrollmentProfile
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Create Mode - Autopilot Profile' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Windows-Autopilot-Profile.json'
                        Name     = 'Windows-Autopilot-Profile.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile",
    "displayName": "Default Autopilot Profile",
    "description": "User driven Azure AD join",
    "deviceNameTemplate": "%SERIAL%",
    "locale": "os-default",
    "preprovisioningAllowed": true,
    "deviceType": "windowsPc",
    "hardwareHashExtractionEnabled": true,
    "hybridAzureADJoinSkipConnectivityCheck": false,
    "outOfBoxExperienceSetting": {
        "deviceUsageType": "singleUser",
        "escapeLinkHidden": true,
        "privacySettingsHidden": true,
        "eulaHidden": true,
        "userType": "standard",
        "keyboardSelectionPageSkipped": true
    }
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should check if profile already exists' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                return @{ id = 'new-profile-id'; displayName = 'Default Autopilot Profile' }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*windowsAutopilotDeploymentProfiles*'
            }
        }

        It 'Should skip profile if it already exists' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(@{ id = 'existing-id'; displayName = 'Default Autopilot Profile' }) }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Skipped'
        }

        It 'Should skip profile when existing object with same name is not tagged by kit' {
            Mock Test-HydrationKitObject { return $false } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*windowsAutopilotDeploymentProfiles?*') {
                    return @{ value = @(@{ id = 'existing-id'; displayName = 'Default Autopilot Profile'; description = 'Manually created profile' }) }
                }
                if ($Method -eq 'GET' -and $Uri -like '*windowsAutopilotDeploymentProfiles/existing-id') {
                    return @{ id = 'existing-id'; displayName = 'Default Autopilot Profile' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Skipped'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*windowsAutopilotDeploymentProfiles*'
            }
        }

        It 'Should create profile if it does not exist' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-profile-id'; displayName = 'Default Autopilot Profile' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Created'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*windowsAutopilotDeploymentProfiles*'
            }
        }

        It 'Should use custom device name template when provided' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    ($Body | ConvertFrom-Json).deviceNameTemplate | Should -Be 'CORP-%SERIAL%'
                    return @{ id = 'new-profile-id'; displayName = 'Default Autopilot Profile' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows -DeviceNameTemplate 'CORP-%SERIAL%'
        }

        It 'Should append hydration marker to description' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    ($Body | ConvertFrom-Json).description | Should -BeLike '*Imported by Intune Hydration Kit*'
                    return @{ id = 'new-profile-id'; displayName = 'Default Autopilot Profile' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows
        }
    }

    Context 'Create Mode - Enrollment Status Page' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Windows-ESP-Profile.json'
                        Name     = 'Windows-ESP-Profile.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration",
    "displayName": "Default ESP Profile",
    "description": "Enrollment status page configuration",
    "showInstallationProgress": true,
    "blockDeviceSetupRetryByUser": false,
    "allowDeviceResetOnInstallFailure": true,
    "allowLogCollectionOnInstallFailure": true,
    "customErrorMessage": "Contact IT support",
    "installProgressTimeoutInMinutes": 60,
    "allowDeviceUseOnInstallFailure": true,
    "trackInstallProgressForAutopilotOnly": true,
    "disableUserStatusTrackingAfterFirstUser": true
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should check if ESP profile already exists' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                return @{ id = 'new-esp-id'; displayName = 'Default ESP Profile' }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations*'
            }
        }

        It 'Should create ESP profile to deviceEnrollmentConfigurations endpoint' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-esp-id'; displayName = 'Default ESP Profile' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*deviceEnrollmentConfigurations*'
            }
        }

        It 'Should create ESP profile with the computed profile display name' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-esp-id'; displayName = 'Default ESP Profile' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be '[IHD] Default ESP Profile'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -like '*deviceEnrollmentConfigurations*' -and
                $Body.displayName -eq '[IHD] Default ESP Profile'
            }
        }

        It 'Should not double-prefix ESP profile names from prefixed templates' {
            Mock Get-Content {
                '{"@odata.type":"#microsoft.graph.windows10EnrollmentCompletionPageConfiguration","displayName":"[IHD] Default ESP Profile","description":"Enrollment status page configuration"}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-esp-id'; displayName = '[IHD] Default ESP Profile' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be '[IHD] Default ESP Profile'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -like '*deviceEnrollmentConfigurations*' -and
                $Body.displayName -eq '[IHD] Default ESP Profile'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Method -eq 'GET' -and
                $Uri -like '*deviceEnrollmentConfigurations?*' -and
                ([string]$Uri).Contains('[IHD] [IHD]')
            }
        }

        It 'Should match legacy unprefixed ESP profiles when template names are prefixed' {
            Mock Get-Content {
                '{"@odata.type":"#microsoft.graph.windows10EnrollmentCompletionPageConfiguration","displayName":"[IHD] Default ESP Profile","description":"Enrollment status page configuration"}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations?*') {
                    return @{
                        value = @(
                            @{
                                id           = 'existing-legacy-esp-id'
                                displayName  = 'Default ESP Profile'
                                description  = 'Imported by Intune Hydration Kit'
                                '@odata.type' = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
                            }
                        )
                    }
                }
                if ($Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations/existing-legacy-esp-id') {
                    return @{ id = 'existing-legacy-esp-id'; displayName = 'Default ESP Profile' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be '[IHD] Default ESP Profile'
            $result[0].Action | Should -Be 'Skipped'
            $result[0].Id | Should -Be 'existing-legacy-esp-id'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $decodedUri = [System.Uri]::UnescapeDataString([string]$Uri)
                $Method -eq 'GET' -and
                $Uri -like '*deviceEnrollmentConfigurations?*' -and
                $decodedUri.Contains("displayName eq 'Default ESP Profile'")
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -like '*deviceEnrollmentConfigurations*'
            }
        }

        It 'Should skip ESP profile when existing object with same name is not tagged by kit' {
            Mock Test-HydrationKitObject { return $false } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations?*') {
                    return @{
                        value = @(
                            @{
                                id           = 'existing-esp-id'
                                displayName  = 'Default ESP Profile'
                                description  = 'Manually created ESP'
                                '@odata.type' = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
                            }
                        )
                    }
                }
                if ($Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations/existing-esp-id') {
                    return @{ id = 'existing-esp-id'; displayName = 'Default ESP Profile' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Skipped'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*deviceEnrollmentConfigurations*'
            }
        }

        It 'Should use Graph error message when ESP profile creation fails' {
            Mock Get-GraphErrorMessage { return 'Detailed ESP Graph error' } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    throw 'Generic wrapper error'
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -Be 'Detailed ESP Graph error'
            Should -Invoke Get-GraphErrorMessage -ModuleName IntuneHydrationKit -Times 1
        }
    }

    Context 'Create Mode - macOS DEP Profile' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\macOS-DEP-Profile.json'
                        Name     = 'macOS-DEP-Profile.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.depMacOSEnrollmentProfile",
    "displayName": "macOS DEP Profile",
    "description": "macOS DEP enrollment profile"
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should use Graph error message when macOS DEP profile creation fails' {
            Mock Get-GraphErrorMessage { return 'Detailed DEP Graph error' } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*depOnboardingSettings/token-1/enrollmentProfiles') {
                    return @{ value = @() }
                }
                if ($Method -eq 'GET' -and $Uri -like '*depOnboardingSettings') {
                    return @{
                        value = @(
                            @{ id = 'token-1'; displayName = 'DEP Token 1' }
                        )
                    }
                }
                if ($Method -eq 'POST' -and $Uri -like '*depOnboardingSettings/token-1/enrollmentProfiles') {
                    throw 'Generic wrapper error'
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform macOS

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -Be 'Detailed DEP Graph error'
            Should -Invoke Get-GraphErrorMessage -ModuleName IntuneHydrationKit -Times 1
        }
    }

    Context 'Create Mode - Autopilot Device Preparation' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Windows-Autopilot-Device-Preparation.json'
                        Name     = 'Windows-Autopilot-Device-Preparation.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "@odata.type": "#microsoft.graph.deviceManagementConfigurationPolicy",
    "name": "Windows Autopilot device preparation - User Driven",
    "description": "Device preparation policy",
    "platforms": "windows10",
    "technologies": "enrollment",
    "templateReference": {
        "templateId": "intune_autopilotDevicePreparation"
    },
    "settings": []
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should check if device preparation policy already exists' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                return @{ id = 'new-policy-id'; name = 'Windows Autopilot device preparation - User Driven' }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*configurationPolicies*'
            }
        }

        It 'Should create device preparation policy to configurationPolicies endpoint' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-policy-id'; name = 'Windows Autopilot device preparation - User Driven' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*configurationPolicies*'
            }
        }

        It 'Should assign device preparation group when policy is created' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*configurationPolicies*') {
                    return @{ value = @() }
                }
                if ($Method -eq 'GET' -and $Uri -like '*groups*') {
                    return @{ value = @(@{ id = 'group-id'; displayName = 'Windows Autopilot device preparation' }) }
                }
                if ($Method -eq 'POST' -and $Uri -like '*configurationPolicies*' -and $Uri -notlike '*setEnrollmentTimeDeviceMembershipTarget*') {
                    return @{ id = 'new-policy-id'; name = 'Windows Autopilot device preparation - User Driven' }
                }
                if ($Method -eq 'POST' -and $Uri -like '*setEnrollmentTimeDeviceMembershipTarget*') {
                    return @{}
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*setEnrollmentTimeDeviceMembershipTarget*'
            }
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Autopilot-Profile.json'; Name = 'Windows-Autopilot-Profile.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile", "displayName": "Test Profile", "outOfBoxExperienceSetting": {}}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should not call POST when WhatIf is specified' {
            Import-IntuneEnrollmentProfile -Platform Windows -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST'
            } -Times 0
        }

        It 'Should return WouldCreate action when WhatIf is specified' {
            $result = Import-IntuneEnrollmentProfile -Platform Windows -WhatIf

            $result[0].Action | Should -Be 'WouldCreate'
        }
    }

    Context 'Delete Mode' {
        BeforeAll {
            $script:deleteEnrollmentTemplateDir = Join-Path ([System.IO.Path]::GetTempPath()) "IHK-EnrollmentDelete-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:deleteEnrollmentTemplateDir -ItemType Directory -Force | Out-Null
            $script:deleteEnrollmentWindowsTemplateFile = Join-Path $script:deleteEnrollmentTemplateDir 'Windows-Autopilot-Profile.json'
            $script:deleteEnrollmentMacTemplateFile = Join-Path $script:deleteEnrollmentTemplateDir 'macOS-DEP-Profile.json'
            '{"displayName":"Profile 1"}' | Set-Content -Path $script:deleteEnrollmentWindowsTemplateFile -Encoding utf8
            '{"displayName":"macOS DEP Profile"}' | Set-Content -Path $script:deleteEnrollmentMacTemplateFile -Encoding utf8

            Mock Get-FilteredTemplates {
                @(Get-Item -Path $script:deleteEnrollmentWindowsTemplateFile)
            } -ModuleName IntuneHydrationKit
            # Return a HashSet that contains all test profile names
            Mock Get-TemplateDisplayNames {
                $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                @('Profile 1', 'Hydration Profile', 'Manual Profile', 'ESP 1', 'Policy 1', 'macOS DEP Profile') | ForEach-Object { [void]$names.Add($_) }
                return $names
            } -ModuleName IntuneHydrationKit
        }

        AfterAll {
            Remove-Item -Path $script:deleteEnrollmentTemplateDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should list existing Autopilot profiles when RemoveExisting is specified' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*windowsAutopilotDeploymentProfiles*') {
                    return @{
                        value = @(
                            @{ id = 'profile-1'; displayName = 'Profile 1'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }
                return @{ value = @() }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -RemoveExisting -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*windowsAutopilotDeploymentProfiles*'
            }
        }

        It 'Should list existing ESP profiles when RemoveExisting is specified' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations*') {
                    return @{
                        value = @(
                            @{ id = 'esp-1'; displayName = 'ESP 1'; description = 'Imported by Intune Hydration Kit'; '@odata.type' = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' }
                        )
                    }
                }
                return @{ value = @() }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -RemoveExisting -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations*'
            }
        }

        It 'Should not delete non-ESP enrollment configurations from the ESP endpoint' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*deviceEnrollmentConfigurations*') {
                    return @{
                        value = @(
                            @{
                                id           = 'limit-config-1'
                                displayName  = 'ESP 1'
                                description  = 'Imported by Intune Hydration Kit'
                                '@odata.type' = '#microsoft.graph.deviceEnrollmentLimitConfiguration'
                            }
                        )
                    }
                }
                return @{ value = @() }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -RemoveExisting -WhatIf

            $espDeletes = @($result | Where-Object { $_.Action -eq 'WouldDelete' -and $_.Type -eq 'EnrollmentStatusPage' })
            $espDeletes | Should -BeNullOrEmpty
        }

        It 'Should list existing device preparation policies when RemoveExisting is specified' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like "*configurationPolicies*enrollment*") {
                    return @{
                        value = @(
                            @{ id = 'policy-1'; name = 'Policy 1'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }
                return @{ value = @() }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -RemoveExisting -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like "*configurationPolicies*enrollment*"
            }
        }

        It 'Should only delete profiles with hydration marker' {
            Mock Test-HydrationKitObject {
                param($Description)
                return $Description -like '*Imported by Intune Hydration Kit*'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*windowsAutopilotDeploymentProfiles*') {
                    return @{
                        value = @(
                            @{ id = 'profile-1'; displayName = 'Hydration Profile'; description = 'Imported by Intune Hydration Kit' },
                            @{ id = 'profile-2'; displayName = 'Manual Profile'; description = 'Created manually' }
                        )
                    }
                }
                return @{ value = @() }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -RemoveExisting -WhatIf

            $deletedProfiles = $result | Where-Object { $_.Action -eq 'WouldDelete' -and $_.Type -eq 'AutopilotDeploymentProfile' }
            $deletedProfiles.Count | Should -Be 1
            $deletedProfiles[0].Name | Should -Be 'Hydration Profile'
        }

        It 'Should delete token-scoped macOS DEP profiles when platform scope is macOS' {
            Mock Get-FilteredTemplates {
                @(Get-Item -Path $script:deleteEnrollmentMacTemplateFile)
            } -ModuleName IntuneHydrationKit
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Uri -like '*windowsAutopilotDeploymentProfiles*' -or
                    $Uri -like '*deviceEnrollmentConfigurations*' -or
                    $Uri -like '*configurationPolicies*enrollment*') {
                    throw 'Windows enrollment endpoint should not be queried'
                }

                if ($Method -eq 'GET' -and $Uri -like '*depOnboardingSettings/token-1/enrollmentProfiles*') {
                    return @{
                        value = @(
                            @{ id = 'mac-profile-1'; displayName = 'macOS DEP Profile'; description = 'Imported by Intune Hydration Kit' }
                            @{ id = 'mac-profile-2'; displayName = 'Manual macOS DEP Profile'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }

                if ($Method -eq 'GET' -and $Uri -like '*depOnboardingSettings?*') {
                    return @{
                        value = @(
                            @{ id = 'token-1'; displayName = 'DEP Token 1' }
                        )
                    }
                }

                if ($Method -eq 'DELETE' -and $Uri -like '*depOnboardingSettings/token-1/enrollmentProfiles/mac-profile-1') {
                    return $null
                }

                if ($Method -eq 'POST' -and $Uri -like '*$batch') {
                    $Body.requests | Should -HaveCount 1
                    $Body.requests[0].method | Should -Be 'DELETE'
                    $Body.requests[0].url | Should -Be '/deviceManagement/depOnboardingSettings/token-1/enrollmentProfiles/mac-profile-1'
                    return @{
                        responses = @(
                            @{ id = '1'; status = 204; body = $null }
                        )
                    }
                }

                throw "Unexpected Graph request: $Method $Uri"
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform macOS -RemoveExisting

            $deletedProfiles = @($result | Where-Object { $_.Action -eq 'Deleted' -and $_.Type -eq 'MacOSDEPEnrollmentProfile' })
            $deletedProfiles | Should -HaveCount 1
            $deletedProfiles[0].Name | Should -Be 'macOS DEP Profile'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0 -ParameterFilter {
                $Uri -like '*windowsAutopilotDeploymentProfiles*' -or
                $Uri -like '*deviceEnrollmentConfigurations*' -or
                $Uri -like '*configurationPolicies*enrollment*'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*$batch'
            }
        }

        It 'Should skip macOS DEP delete when no macOS enrollment templates exist' {
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit
            Mock Invoke-MgGraphRequest {
                throw "Graph should not be queried without scoped macOS template names"
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform macOS -RemoveExisting

            $skippedProfiles = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Type -eq 'MacOSDEPEnrollmentProfile' })
            $skippedProfiles | Should -HaveCount 1
            $skippedProfiles[0].Status | Should -BeLike '*No macOS enrollment templates found*'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Times 0
        }
    }

    Context 'Error Handling' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Autopilot-Profile.json'; Name = 'Windows-Autopilot-Profile.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile", "displayName": "Test Profile", "outOfBoxExperienceSetting": {}}'
            } -ModuleName IntuneHydrationKit
        }

        It 'Should handle API errors gracefully' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
                if ($Method -eq 'POST') { throw "API Error" }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result[0].Action | Should -Be 'Failed'
        }

        It 'Should return empty array when no templates found' {
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -BeNullOrEmpty
        }

        It 'Should skip templates with missing @odata.type' {
            Mock Get-Content {
                '{"displayName": "Invalid Template", "description": "Missing odata type"}'
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result[0].Action | Should -Be 'Skipped'
            $result[0].Status | Should -BeLike '*Missing @odata.type*'
        }
    }

    Context 'Platform Filtering' {
        It 'Should pass platform parameter to Get-FilteredTemplates' {
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows

            Should -Invoke Get-FilteredTemplates -ModuleName IntuneHydrationKit -ParameterFilter {
                $Platform -contains 'Windows'
            }
        }
    }

    Context 'Result Structure' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Autopilot-Profile.json'; Name = 'Windows-Autopilot-Profile.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"@odata.type": "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile", "displayName": "Test Profile", "outOfBoxExperienceSetting": {}}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
                return @{ id = 'profile-123'; displayName = 'Test Profile' }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return results with correct structure' {
            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be '[IHD] Test Profile'
            $result[0].Type | Should -Be 'AutopilotDeploymentProfile'
            $result[0].Id | Should -Be 'profile-123'
            $result[0].Action | Should -Be 'Created'
        }
    }
}
