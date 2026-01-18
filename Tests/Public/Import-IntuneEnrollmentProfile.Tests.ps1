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
                param($Method, $Uri)
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
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @(@{ id = 'existing-id'; displayName = 'Default Autopilot Profile' }) }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneEnrollmentProfile -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Skipped'
        }

        It 'Should create profile if it does not exist' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
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
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    $Body.deviceNameTemplate | Should -Be 'CORP-%SERIAL%'
                    return @{ id = 'new-profile-id'; displayName = 'Default Autopilot Profile' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneEnrollmentProfile -Platform Windows -DeviceNameTemplate 'CORP-%SERIAL%'
        }

        It 'Should append hydration marker to description' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    $Body.description | Should -BeLike '*Imported by Intune Hydration Kit*'
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
                param($Method, $Uri)
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
                param($Method, $Uri)
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
                param($Method, $Uri)
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
                param($Method, $Uri)
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
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit
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
            $result[0].Name | Should -Be 'Test Profile'
            $result[0].Type | Should -Be 'AutopilotDeploymentProfile'
            $result[0].Id | Should -Be 'profile-123'
            $result[0].Action | Should -Be 'Created'
        }
    }
}
