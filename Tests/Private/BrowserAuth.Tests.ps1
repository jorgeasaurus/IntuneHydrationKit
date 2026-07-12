#Requires -Modules Pester

BeforeAll {
    $script:ModuleRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    . (Join-Path $script:ModuleRoot 'Private/Auth/ConvertTo-HydrationOAuthScope.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Get-HydrationGraphEnvironmentInfo.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Get-HydrationBrowserAuthLogoDataUri.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/New-HydrationBrowserAuthResponseHtml.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Get-HydrationFreeTcpPort.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/New-HydrationCodeVerifier.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/New-HydrationCodeChallenge.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/New-HydrationOAuthAuthorizeUri.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Invoke-HydrationOAuthTokenRequest.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Get-HydrationOAuthCallbackResult.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Get-HydrationTenantIdFromAccessToken.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Get-HydrationTokenViaBrowser.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Connect-HydrationGraphViaBrowser.ps1')

    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        function Connect-MgGraph { }
    }
    if (-not (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue)) {
        function Disconnect-MgGraph { }
    }
    if (-not (Get-Command Format-HydrationDisplayMessage -ErrorAction SilentlyContinue)) {
        function Format-HydrationDisplayMessage {
            param([string]$Message)
            return $Message
        }
    }
}

Describe 'Browser authentication helpers' {
    BeforeAll {
        function New-TestJwt {
            param([string]$PayloadJson)

            $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PayloadJson)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            return "header.$payload.signature"
        }
    }

    Context 'ConvertTo-HydrationOAuthScope' {
        It 'Should prefix bare Graph scopes with the selected Graph endpoint' {
            $result = ConvertTo-HydrationOAuthScope `
                -Scopes @('User.Read', 'DeviceManagementConfiguration.ReadWrite.All') `
                -GraphEndpoint 'https://graph.microsoft.us'

            $result | Should -Contain 'https://graph.microsoft.us/User.Read'
            $result | Should -Contain 'https://graph.microsoft.us/DeviceManagementConfiguration.ReadWrite.All'
        }

        It 'Should preserve fully qualified and OIDC scopes' {
            $result = ConvertTo-HydrationOAuthScope `
                -Scopes @('https://graph.microsoft.com/User.Read', 'openid', 'profile') `
                -GraphEndpoint 'https://graph.microsoft.com'

            $result | Should -Contain 'https://graph.microsoft.com/User.Read'
            $result | Should -Contain 'openid'
            $result | Should -Contain 'profile'
        }

        It 'Should not add refresh-token scopes implicitly' {
            $result = ConvertTo-HydrationOAuthScope `
                -Scopes @('User.Read') `
                -GraphEndpoint 'https://graph.microsoft.com'

            $result | Should -Not -Contain 'offline_access'
        }
    }

    Context 'Get-HydrationGraphEnvironmentInfo' {
        It 'Should include the US Gov authority host' {
            $result = Get-HydrationGraphEnvironmentInfo -Environment USGov

            $result.Endpoint | Should -Be 'https://graph.microsoft.us'
            $result.AuthorityHost | Should -Be 'https://login.microsoftonline.us'
        }

        It 'Should include the China authority host' {
            $result = Get-HydrationGraphEnvironmentInfo -Environment China

            $result.Endpoint | Should -Be 'https://microsoftgraph.chinacloudapi.cn'
            $result.AuthorityHost | Should -Be 'https://login.chinacloudapi.cn'
        }
    }

    Context 'New-HydrationOAuthAuthorizeUri' {
        BeforeAll {
            function ConvertFrom-TestQueryString {
                param([Parameter(Mandatory)][string]$Uri)

                $query = ([uri]$Uri).Query.TrimStart('?')
                $values = @{}
                foreach ($pair in ($query -split '&')) {
                    $parts = $pair -split '=', 2
                    $values[[uri]::UnescapeDataString($parts[0])] = [uri]::UnescapeDataString($parts[1])
                }

                return $values
            }
        }

        It 'Should request account selection by default' {
            $uri = New-HydrationOAuthAuthorizeUri `
                -ClientId 'client-id' `
                -TenantId 'organizations' `
                -AuthorityHost 'https://login.microsoftonline.com' `
                -RedirectUri 'http://localhost:12345/' `
                -Scopes @('https://graph.microsoft.com/DeviceManagementConfiguration.ReadWrite.All', 'https://graph.microsoft.com/Policy.ReadWrite.ConditionalAccess') `
                -State 'state-value' `
                -CodeChallenge 'challenge-value'

            $query = ConvertFrom-TestQueryString -Uri $uri

            $query.prompt | Should -Be 'select_account'
            $query.scope | Should -Be 'https://graph.microsoft.com/DeviceManagementConfiguration.ReadWrite.All https://graph.microsoft.com/Policy.ReadWrite.ConditionalAccess'
            $query.response_type | Should -Be 'code'
            $query.code_challenge_method | Should -Be 'S256'
        }

        It 'Should request an OAuth consent prompt when specified' {
            $uri = New-HydrationOAuthAuthorizeUri `
                -ClientId 'client-id' `
                -TenantId 'organizations' `
                -AuthorityHost 'https://login.microsoftonline.com' `
                -RedirectUri 'http://localhost:12345/' `
                -Scopes @('https://graph.microsoft.com/DeviceManagementConfiguration.ReadWrite.All') `
                -State 'state-value' `
                -CodeChallenge 'challenge-value' `
                -Prompt consent

            $query = ConvertFrom-TestQueryString -Uri $uri

            $query.prompt | Should -Be 'consent'
            $query.scope | Should -Be 'https://graph.microsoft.com/DeviceManagementConfiguration.ReadWrite.All'
            $query.response_type | Should -Be 'code'
            $query.code_challenge_method | Should -Be 'S256'
        }
    }

    Context 'New-HydrationBrowserAuthResponseHtml' {
        It 'Should render themed success HTML with the IHD logo' {
            $html = New-HydrationBrowserAuthResponseHtml -Status Success

            $html | Should -Match 'Intune Hydration Kit'
            $html | Should -Match 'Authentication complete'
            $html | Should -Match 'data:image/png;base64,'
            $html | Should -Match 'By <a href="https://github.com/jorgeasaurus"'
            $html | Should -Match '>Jorgeasaurus</a>'
            $html | Should -Not -Match '\{\{TITLE\}\}'
        }

        It 'Should HTML-encode error messages' {
            $html = New-HydrationBrowserAuthResponseHtml -Status Error -Message '<script>alert(1)</script>'

            $html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
            $html | Should -Not -Match '<script>alert'
        }
    }

    Context 'Get-HydrationOAuthCallbackResult' {
        It 'Should reject callbacks with mismatched OAuth state before reporting success' {
            $result = Get-HydrationOAuthCallbackResult `
                -Code 'fake-code' `
                -AuthError '' `
                -ErrorDescription '' `
                -ReturnedState 'wrong-state' `
                -ExpectedState 'expected-state'

            $result.Status | Should -Be 'Error'
            $result.Message | Should -Match 'OAuth state mismatch'
            $result.ErrorMessage | Should -Be 'OAuth state mismatch. Aborting authentication.'
        }

        It 'Should accept callbacks with a code and matching OAuth state' {
            $result = Get-HydrationOAuthCallbackResult `
                -Code 'fake-code' `
                -AuthError '' `
                -ErrorDescription '' `
                -ReturnedState 'expected-state' `
                -ExpectedState 'expected-state'

            $result.Status | Should -Be 'Success'
            $result.ErrorMessage | Should -BeNullOrEmpty
        }
    }

    Context 'Get-HydrationTenantIdFromAccessToken' {
        It 'Should extract tenant ID from a JWT access token' {
            $token = New-TestJwt -PayloadJson '{"tid":"12345678-1234-1234-1234-123456789abc"}'

            Get-HydrationTenantIdFromAccessToken -AccessToken $token |
                Should -Be '12345678-1234-1234-1234-123456789abc'
        }

        It 'Should return null when the token is not a JWT with a tenant claim' {
            Get-HydrationTenantIdFromAccessToken -AccessToken 'opaque-token' |
                Should -BeNullOrEmpty
        }
    }

    Context 'Connect-HydrationGraphViaBrowser' {
        BeforeEach {
            Mock Get-HydrationGraphEnvironmentInfo {
                @{
                    Endpoint      = 'https://graph.microsoft.com'
                    AuthorityHost = 'https://login.microsoftonline.com'
                }
            }
            Mock ConvertTo-HydrationOAuthScope { @('https://graph.microsoft.com/User.Read') }
            Mock Disconnect-MgGraph { }
        }

        It 'Should retry with a fresh browser sign-in when token connection fails' {
            $script:ConnectAttempts = 0
            $token = New-TestJwt -PayloadJson '{"tid":"12345678-1234-1234-1234-123456789abc"}'

            Mock Get-HydrationTokenViaBrowser { [pscustomobject]@{ access_token = $token } }
            Mock Connect-MgGraph {
                $script:ConnectAttempts++
                if ($script:ConnectAttempts -eq 1) {
                    throw 'browser token rejected'
                }
            }

            $result = Connect-HydrationGraphViaBrowser -TenantId 'organizations' -Scopes @('User.Read') -Environment Global

            $result.TenantId | Should -Be '12345678-1234-1234-1234-123456789abc'
            Should -Invoke Get-HydrationTokenViaBrowser -Times 2
            Should -Invoke Connect-MgGraph -Times 2
            Should -Invoke Disconnect-MgGraph -Times 2
        }

        It 'Should not retry indefinitely when fresh browser token connection fails' {
            Mock Get-HydrationTokenViaBrowser { [pscustomobject]@{ access_token = 'browser-access' } }
            Mock Connect-MgGraph { throw 'browser token rejected' }

            {
                Connect-HydrationGraphViaBrowser -TenantId '12345678-1234-1234-1234-123456789abc' -Scopes @('User.Read') -Environment Global
            } | Should -Throw

            Should -Invoke Get-HydrationTokenViaBrowser -Times 2
            Should -Invoke Connect-MgGraph -Times 2
            Should -Invoke Disconnect-MgGraph -Times 2
        }

        It 'Should fail tenantless browser auth when the connected token has no tenant claim' {
            Mock Get-HydrationTokenViaBrowser { [pscustomobject]@{ access_token = 'opaque-token' } }
            Mock Connect-MgGraph { }

            {
                Connect-HydrationGraphViaBrowser -TenantId 'organizations' -Scopes @('User.Read') -Environment Global
            } | Should -Throw '*Unable to determine the signed-in tenant ID*'

            Should -Invoke Get-HydrationTokenViaBrowser -Times 1
            Should -Invoke Connect-MgGraph -Times 1
            Should -Invoke Disconnect-MgGraph -Times 1
        }

        It 'Should pass forced consent to browser token acquisition when requested' {
            $token = New-TestJwt -PayloadJson '{"tid":"12345678-1234-1234-1234-123456789abc"}'
            Mock Get-HydrationTokenViaBrowser { [pscustomobject]@{ access_token = $token } }
            Mock Connect-MgGraph { }

            $result = Connect-HydrationGraphViaBrowser -TenantId 'organizations' -Scopes @('User.Read') -Environment Global -ForceConsent

            $result.TenantId | Should -Be '12345678-1234-1234-1234-123456789abc'
            Should -Invoke Get-HydrationTokenViaBrowser -Times 1 -ParameterFilter {
                $ForceConsent -eq $true
            }
        }
    }
}
