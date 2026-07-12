#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Import-IntuneNotificationTemplate' {
    BeforeAll {
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return 'Test error message' } -ModuleName IntuneHydrationKit
    }

    Context 'Localized message failures' {
        BeforeEach {
            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Notification.json'
                        Name     = 'Notification.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "displayName": "Enrollment notification",
    "brandingOptions": "none",
    "localizedMessages": [
        {
            "locale": "en-us",
            "subject": "Welcome",
            "messageTemplate": "Welcome"
        },
        {
            "locale": "fr-fr",
            "subject": "Bienvenue",
            "messageTemplate": "Bienvenue"
        }
    ]
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return partial status when a localized message fails after parent creation' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST' -and $Uri -eq 'beta/deviceManagement/notificationMessageTemplates') {
                    return @{ id = 'new-template-id' }
                }
                if ($Method -eq 'POST' -and $Uri -like '*localizedNotificationMessages') {
                    throw 'Localized message failed'
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneNotificationTemplate -TemplatePath $PSScriptRoot

            $result[0].Action | Should -Be 'Created'
            $result[0].Status | Should -Be 'Partial: 2 of 2 localized messages failed'
        }
    }
}
