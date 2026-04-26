#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Import-IntuneNotificationTemplate' {
    BeforeAll {
        # Catch-all mock prevents real Graph API calls (which would hang on auth)
        Mock Invoke-MgGraphRequest { return @{ value = @() } } -ModuleName IntuneHydrationKit
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit

        InModuleScope IntuneHydrationKit {
            $script:TemplatesPath = 'TestDrive:\Templates'
            $script:ImportPrefix = '[IHD] '
        }
    }

    Context 'Parameter Validation' {
        It 'Should have TemplatePath parameter' {
            $command = Get-Command Import-IntuneNotificationTemplate
            $param = $command.Parameters['TemplatePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Import-IntuneNotificationTemplate
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneNotificationTemplate
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Template Loading' {
        It 'Should return empty array when template directory does not exist' {
            $result = Import-IntuneNotificationTemplate -TemplatePath 'TestDrive:\NonExistent'

            $result | Should -BeNullOrEmpty
        }

        It 'Should return empty array when no templates found' {
            New-Item -Path 'TestDrive:\EmptyNotifications' -ItemType Directory -Force | Out-Null

            Mock Get-HydrationTemplates { @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath 'TestDrive:\EmptyNotifications'

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Create Mode' {
        BeforeAll {
            $notifDir = Join-Path 'TestDrive:' 'NotifTemplates'
            New-Item -Path $notifDir -ItemType Directory -Force | Out-Null
            $templateJson = @{
                displayName       = 'Compliance Reminder'
                brandingOptions   = 'includeCompanyLogo'
                localizedMessages = @(
                    @{
                        locale          = 'en-us'
                        subject         = 'Device Compliance Required'
                        messageTemplate = 'Your device is not compliant.'
                        isDefault       = $true
                    }
                )
            } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $notifDir 'ComplianceReminder.json') -Value $templateJson

            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = (Join-Path 'TestDrive:' 'NotifTemplates\ComplianceReminder.json')
                        Name     = 'ComplianceReminder.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Copy-DeepObject {
                param($InputObject)
                return $InputObject
            } -ModuleName IntuneHydrationKit
        }

        It 'Should create notification template and localized messages' {
            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'POST' -and $Uri -like '*notificationMessageTemplates') {
                    return @{ id = 'new-template-id'; displayName = '[IHD] Compliance Reminder' }
                }
                if ($Method -eq 'POST' -and $Uri -like '*localizedNotificationMessages*') {
                    return @{ id = 'locale-id' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifTemplates')

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 1
            $created[0].Name | Should -Be '[IHD] Compliance Reminder'

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*localizedNotificationMessages*'
            }
        }

        It 'Should skip template that already exists (verified by targeted GET)' {
            Mock Get-GraphPagedResults {
                param($ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'existing-id'; displayName = '[IHD] Compliance Reminder' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            # Targeted GET succeeds → template genuinely exists
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*notificationMessageTemplates/existing-id*') {
                    return @{ id = 'existing-id'; displayName = '[IHD] Compliance Reminder' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifTemplates')

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Status -eq 'Already exists' })
            $skipped.Count | Should -Be 1
        }

        It 'Should skip template matching legacy unprefixed name (verified by targeted GET)' {
            Mock Get-GraphPagedResults {
                param($ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'legacy-id'; displayName = 'Compliance Reminder' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            # Targeted GET succeeds → legacy template genuinely exists
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -like '*notificationMessageTemplates/legacy-id*') {
                    return @{ id = 'legacy-id'; displayName = 'Compliance Reminder' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifTemplates')

            $skipped = @($result | Where-Object { $_.Action -eq 'Skipped' -and $_.Status -like '*legacy*' })
            $skipped.Count | Should -Be 1
        }

        It 'Should create template when prefetch returns stale data (targeted GET returns 404)' {
            Mock Get-GraphPagedResults {
                param($ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'stale-id'; displayName = '[IHD] Compliance Reminder' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                # Targeted GET fails → template was deleted (stale listing)
                if ($Method -eq 'GET' -and $Uri -like '*notificationMessageTemplates/stale-id*') {
                    throw [System.Net.Http.HttpRequestException]::new(
                        "Response status code does not indicate success: 404 (Not Found).",
                        $null,
                        [System.Net.HttpStatusCode]::NotFound
                    )
                }
                if ($Method -eq 'POST' -and $Uri -like '*notificationMessageTemplates') {
                    return @{ id = 'new-id'; displayName = '[IHD] Compliance Reminder' }
                }
                if ($Method -eq 'POST' -and $Uri -like '*localizedNotificationMessages*') {
                    return @{ id = 'locale-id' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifTemplates')

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 1
            $created[0].Name | Should -Be '[IHD] Compliance Reminder'
        }

        It 'Should report partial success when localized message creation fails' {
            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'POST' -and $Uri -eq 'beta/deviceManagement/notificationMessageTemplates') {
                    return @{ id = 'new-template-id'; displayName = '[IHD] Compliance Reminder' }
                }
                if ($Method -eq 'POST' -and $Uri -like '*localizedNotificationMessages*') {
                    throw [System.Exception]::new('Localized message failed')
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifTemplates')

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $created.Count | Should -Be 1
            $created[0].Status | Should -BeLike 'PartialSuccess*'
        }
    }

    Context 'WhatIf Support' {
        BeforeAll {
            $notifDir = Join-Path 'TestDrive:' 'NotifWhatIf'
            New-Item -Path $notifDir -ItemType Directory -Force | Out-Null
            $templateJson = @{
                displayName     = 'WhatIf Template'
                brandingOptions = 'includeCompanyLogo'
            } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $notifDir 'WhatIfTemplate.json') -Value $templateJson

            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = (Join-Path 'TestDrive:' 'NotifWhatIf\WhatIfTemplate.json')
                        Name     = 'WhatIfTemplate.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit
            Mock Copy-DeepObject { param($InputObject) return $InputObject } -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate without calling Graph POST' {
            Mock Invoke-MgGraphRequest -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifWhatIf') -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'WouldCreate'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST'
            } -Times 0
        }
    }

    Context 'Delete Mode' {
        BeforeAll {
            $notifDir = Join-Path 'TestDrive:' 'NotifDelete'
            New-Item -Path $notifDir -ItemType Directory -Force | Out-Null
            $templateJson = @{
                displayName     = 'Delete Template'
                brandingOptions = 'includeCompanyLogo'
            } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $notifDir 'DeleteTemplate.json') -Value $templateJson

            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = (Join-Path 'TestDrive:' 'NotifDelete\DeleteTemplate.json')
                        Name     = 'DeleteTemplate.json'
                    })
            } -ModuleName IntuneHydrationKit
        }

        It 'Should delete templates matching template file names' {
            Mock Get-GraphPagedResults {
                param($ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'tmpl-1'; displayName = '[IHD] Delete Template' },
                        @{ id = 'tmpl-2'; displayName = 'Unrelated Template' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'DELETE') { return $null }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifDelete') -RemoveExisting -Confirm:$false

            $deleted = @($result | Where-Object { $_.Action -eq 'Deleted' })
            $deleted.Count | Should -Be 1
            $deleted[0].Name | Should -Be '[IHD] Delete Template'
        }

        It 'Should return WouldDelete in WhatIf mode' {
            Mock Get-GraphPagedResults {
                param($ProcessItems)
                if ($ProcessItems) {
                    & $ProcessItems @(
                        @{ id = 'tmpl-1'; displayName = 'Delete Template' }
                    )
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifDelete') -RemoveExisting -WhatIf

            $wouldDelete = @($result | Where-Object { $_.Action -eq 'WouldDelete' })
            $wouldDelete.Count | Should -Be 1
        }
    }

    Context 'Error Handling' {
        It 'Should handle missing displayName in template' {
            $badDir = Join-Path 'TestDrive:' 'NotifBad'
            New-Item -Path $badDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $badDir 'Bad.json') -Value '{"brandingOptions": "none"}'

            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = (Join-Path 'TestDrive:' 'NotifBad\Bad.json')
                        Name     = 'Bad.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-GraphPagedResults -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath (Join-Path 'TestDrive:' 'NotifBad')

            $failed = @($result | Where-Object { $_.Action -eq 'Failed' })
            $failed.Count | Should -Be 1
            $failed[0].Status | Should -BeLike '*Missing displayName*'
        }
    }
}
