#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Import-IntuneRemediation' {
    Context 'When creating the bundled Proactive remediation pack in WhatIf mode' {
        BeforeEach {
            Mock Get-IntuneProactiveRemediationAvailability {
                [pscustomobject]@{
                    IsAvailable = $true
                    Status      = 'Available'
                    Message     = 'Proactive remediations are available.'
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-HydrationGraphRequest { } -ModuleName IntuneHydrationKit
        }

        It 'Reports the six unassigned remediations without writing to Graph' {
            $result = Import-IntuneRemediation -WhatIf

            $result | Should -HaveCount 6
            $result.Name | Should -Be @(
                '[IHD] Windows - Disk Pressure Cleanup',
                '[IHD] Windows - Device Health Reporting',
                '[IHD] Windows - Automatic Time Zone',
                '[IHD] Windows - BitLocker Recovery Key Escrow',
                '[IHD] Windows - Defender Signature Freshness',
                '[IHD] Windows - Recovery Environment Health'
            )
            $result.Action | Should -Be @('WouldCreate', 'WouldCreate', 'WouldCreate', 'WouldCreate', 'WouldCreate', 'WouldCreate')
            $result.Type | Should -Be @('Remediation', 'Remediation', 'Remediation', 'Remediation', 'Remediation', 'Remediation')
            Should -Invoke Invoke-HydrationGraphRequest -Exactly 6 -ParameterFilter { $Method -eq 'GET' } -ModuleName IntuneHydrationKit
        }
    }

    Context 'When creating the bundled Proactive remediation pack' {
        BeforeEach {
            $script:postedBodies = @()
            Mock Get-IntuneProactiveRemediationAvailability {
                [pscustomobject]@{
                    IsAvailable = $true
                    Status      = 'Available'
                    Message     = 'Proactive remediations are available.'
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-HydrationGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }

                if ($Method -eq 'POST') {
                    $script:postedBodies += $Body
                    return @{ id = "remediation-$($script:postedBodies.Count)" }
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Creates unassigned system packages and preserves detection-only reporting' {
            $result = Import-IntuneRemediation

            $result.Action | Should -Be @('Created', 'Created', 'Created', 'Created', 'Created', 'Created')
            $script:postedBodies | Should -HaveCount 6
            $script:postedBodies.runAsAccount | Should -Be @('system', 'system', 'system', 'system', 'system', 'system')
            $script:postedBodies.runAs32Bit | Should -Be @($false, $false, $false, $false, $false, $false)
            $script:postedBodies | ForEach-Object { $_.Contains('assignments') } | Should -Be @($false, $false, $false, $false, $false, $false)
            $script:postedBodies[1].Contains('remediationScriptContent') | Should -Be $false
            $script:postedBodies[1].description | Should -Match 'This detection-only package makes no device changes'
        }

        It 'Constrains the new remediation actions to their intended repair boundaries' {
            $null = Import-IntuneRemediation
            $bodiesByName = @{}
            foreach ($body in $script:postedBodies) {
                $bodiesByName[$body.displayName] = $body
            }

            $bitLockerRemediation = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($bodiesByName['[IHD] Windows - BitLocker Recovery Key Escrow'].remediationScriptContent))
            $defenderRemediation = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($bodiesByName['[IHD] Windows - Defender Signature Freshness'].remediationScriptContent))
            $automaticTimeZoneRemediation = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($bodiesByName['[IHD] Windows - Automatic Time Zone'].remediationScriptContent))
            $winReRemediation = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($bodiesByName['[IHD] Windows - Recovery Environment Health'].remediationScriptContent))

            $bitLockerRemediation | Should -Match 'BackupToAAD-BitLockerKeyProtector'
            $bitLockerRemediation | Should -Not -Match '(?i)(Add|Remove)-BitLockerKeyProtector'
            $defenderRemediation | Should -Match 'Update-MpSignature'
            $defenderRemediation | Should -Not -Match '(?i)Set-MpPreference'
            $automaticTimeZoneRemediation | Should -Match "Start-Service -Name 'tzautoupdate' -ErrorAction Stop"
            $automaticTimeZoneRemediation | Should -Match 'Failed to start the automatic time zone service'
            $winReRemediation | Should -Match '\$reAgentExecutable\s+/enable'
            $winReRemediation | Should -Not -Match '(?i)(/disable|/setreimage|bcdedit|diskpart)'
        }
    }

    Context 'When deleting remediation packages' {
        BeforeEach {
            $script:deletedUris = @()
            Mock Get-IntuneProactiveRemediationAvailability {
                [pscustomobject]@{
                    IsAvailable = $true
                    Status      = 'Available'
                    Message     = 'Proactive remediations are available.'
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-HydrationGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'Disk%20Pressure%20Cleanup') {
                    return @{
                        value = @(
                            @{
                                id          = 'owned-disk-cleanup'
                                displayName = '[IHD] Windows - Disk Pressure Cleanup'
                                description = "Imported by Intune Hydration Kit`nImported from Proactive Remediation Pack`nRemediationTemplateId: windows-disk-pressure-cleanup"
                            },
                            @{
                                id          = 'unowned-disk-cleanup'
                                displayName = '[IHD] Windows - Disk Pressure Cleanup'
                                description = 'Created outside Intune Hydration Kit'
                            }
                        )
                    }
                }

                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }

                if ($Method -eq 'DELETE') {
                    $script:deletedUris += $Uri
                    return @{}
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Deletes only the matching hydration-owned template package' {
            $result = Import-IntuneRemediation -RemoveExisting

            $result | Should -HaveCount 1
            $result[0].Id | Should -Be 'owned-disk-cleanup'
            $result[0].Action | Should -Be 'Deleted'
            $script:deletedUris | Should -Be @('beta/deviceManagement/deviceHealthScripts/owned-disk-cleanup')
        }

        It 'Does not treat a template ID prefix as ownership' {
            Mock Invoke-HydrationGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'Disk%20Pressure%20Cleanup') {
                    return @{
                        value = @(
                            @{
                                id          = 'suffix-template-id'
                                displayName = '[IHD] Windows - Disk Pressure Cleanup'
                                description = "Imported by Intune Hydration Kit`nImported from Proactive Remediation Pack`nRemediationTemplateId: windows-disk-pressure-cleanup-v2"
                            }
                        )
                    }
                }

                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }

                if ($Method -eq 'DELETE') {
                    $script:deletedUris += $Uri
                    return @{}
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneRemediation -TemplateId 'windows-disk-pressure-cleanup' -RemoveExisting

            $result | Should -BeNullOrEmpty
            $script:deletedUris | Should -BeNullOrEmpty
        }
    }

    Context 'When planning updates in WhatIf mode' {
        BeforeEach {
            Mock Get-IntuneProactiveRemediationAvailability {
                [pscustomobject]@{
                    IsAvailable = $true
                    Status      = 'Available'
                    Message     = 'Proactive remediations are available.'
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-HydrationGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match '/assignments') {
                    return @{ value = @() }
                }

                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id          = 'stale-remediation'
                                displayName = '[IHD] Windows - Disk Pressure Cleanup'
                                description = "Imported by Intune Hydration Kit`nImported from Proactive Remediation Pack`nRemediationTemplateId: windows-disk-pressure-cleanup`nRemediationFingerprint: stale"
                            }
                        )
                    }
                }

                throw 'WhatIf must not mutate Graph.'
            } -ModuleName IntuneHydrationKit
        }

        It 'Resolves existing owned state and reports WouldUpdate' {
            $result = Import-IntuneRemediation -TemplateId 'windows-disk-pressure-cleanup' -WhatIf

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'WouldUpdate'
            $result[0].Id | Should -Be 'stale-remediation'
            Should -Invoke Invoke-HydrationGraphRequest -Exactly 2 -ParameterFilter { $Method -eq 'GET' } -ModuleName IntuneHydrationKit
            Should -Invoke Invoke-HydrationGraphRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'GET' -and $Uri -match '/assignments'
            } -ModuleName IntuneHydrationKit
        }
    }

    Context 'When an owned remediation was assigned after import' {
        BeforeEach {
            Mock Get-IntuneProactiveRemediationAvailability {
                [pscustomobject]@{
                    IsAvailable = $true
                    Status      = 'Available'
                    Message     = 'Proactive remediations are available.'
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-HydrationGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match '/assignments') {
                    return @{ value = @(@{ id = 'manual-assignment' }) }
                }

                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id          = 'stale-remediation'
                                displayName = '[IHD] Windows - Disk Pressure Cleanup'
                                description = "Imported by Intune Hydration Kit`nImported from Proactive Remediation Pack`nRemediationTemplateId: windows-disk-pressure-cleanup`nRemediationFingerprint: stale"
                            }
                        )
                    }
                }

                throw 'Assigned remediations must not be updated.'
            } -ModuleName IntuneHydrationKit
        }

        It 'Refuses to update the assigned package and preserves its deployment' {
            $result = Import-IntuneRemediation -TemplateId 'windows-disk-pressure-cleanup'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -Be 'Assigned'
            Should -Invoke Invoke-HydrationGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'PATCH' } -ModuleName IntuneHydrationKit
        }
    }

    Context 'When planning an update for an assigned remediation' {
        BeforeEach {
            Mock Get-IntuneProactiveRemediationAvailability {
                [pscustomobject]@{
                    IsAvailable = $true
                    Status      = 'Available'
                    Message     = 'Proactive remediations are available.'
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-HydrationGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match '/assignments') {
                    return @{ value = @(@{ id = 'manual-assignment' }) }
                }

                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id          = 'stale-remediation'
                                displayName = '[IHD] Windows - Disk Pressure Cleanup'
                                description = "Imported by Intune Hydration Kit`nImported from Proactive Remediation Pack`nRemediationTemplateId: windows-disk-pressure-cleanup`nRemediationFingerprint: stale"
                            }
                        )
                    }
                }

                throw 'WhatIf must not mutate Graph.'
            } -ModuleName IntuneHydrationKit
        }

        It 'Reports that the assigned package cannot be updated' {
            $result = Import-IntuneRemediation -TemplateId 'windows-disk-pressure-cleanup' -WhatIf

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -Be 'Assigned'
            Should -Invoke Invoke-HydrationGraphRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'GET' -and $Uri -match '/assignments'
            } -ModuleName IntuneHydrationKit
            Should -Invoke Invoke-HydrationGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'PATCH' } -ModuleName IntuneHydrationKit
        }
    }
}
