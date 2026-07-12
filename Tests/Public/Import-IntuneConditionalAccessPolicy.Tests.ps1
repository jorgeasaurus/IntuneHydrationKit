#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Import-IntuneConditionalAccessPolicy' {
    BeforeAll {
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return 'Test error message' } -ModuleName IntuneHydrationKit
        Mock Test-ConditionalAccessPolicyRequiresP2 { return $false } -ModuleName IntuneHydrationKit
        Mock Test-ConditionalAccessPolicyRequiresPreview { return $null } -ModuleName IntuneHydrationKit
    }

    Context 'OData annotation cleanup' {
        BeforeEach {
            Mock Get-HydrationTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\ConditionalAccess.json'
                        Name     = 'ConditionalAccess.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "displayName": "Require phishing-resistant MFA",
    "state": "disabled",
    "conditions": {
        "users": {
            "includeUsers": [ "All" ],
            "includeGuestsOrExternalUsers": {
                "@odata.type": "#microsoft.graph.conditionalAccessAllExternalTenants",
                "externalTenants@odata.context": "https://graph.microsoft.com/beta/$metadata#identity/conditionalAccess/policies"
            }
        },
        "applications": {
            "includeApplications": [ "All" ]
        }
    },
    "grantControls": {
        "operator": "OR",
        "builtInControls": [],
        "authenticationStrength": {
            "id": "00000000-0000-0000-0000-000000000004",
            "authenticationStrength@odata.context": "https://graph.microsoft.com/beta/$metadata#policies/authenticationStrengthPolicies/$entity"
        }
    }
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should remove prefixed OData annotations but keep @odata.type' {
            $postedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET' -and $Uri -eq 'beta/subscribedSkus') {
                    return @{ value = @() }
                }
                if ($Method -eq 'GET' -and $Uri -like '*conditionalAccess/policies*') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    $script:postedBody = $Body
                    return @{ id = 'new-policy-id' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneConditionalAccessPolicy -TemplatePath $PSScriptRoot

            $script:postedBody | Should -Not -Match 'authenticationStrength@odata\.context'
            $script:postedBody | Should -Not -Match 'externalTenants@odata\.context'
            $script:postedBody | Should -Match '"@odata.type"'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'beta/identity/conditionalAccess/policies'
            } -Times 1
        }
    }
}
