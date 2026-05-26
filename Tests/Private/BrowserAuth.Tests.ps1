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
    . (Join-Path $script:ModuleRoot 'Private/Auth/Invoke-HydrationOAuthTokenRequest.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Auth/Get-HydrationOAuthCallbackResult.ps1')
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

    Context 'New-HydrationBrowserAuthResponseHtml' {
        It 'Should render themed success HTML with the IHD logo' {
            $html = New-HydrationBrowserAuthResponseHtml -Status Success

            $html | Should -Match 'Intune Hydration Kit'
            $html | Should -Match 'Authentication complete'
            $html | Should -Match 'data:image/png;base64,'
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

            Mock Get-HydrationTokenViaBrowser { [pscustomobject]@{ access_token = 'browser-access' } }
            Mock Connect-MgGraph {
                $script:ConnectAttempts++
                if ($script:ConnectAttempts -eq 1) {
                    throw 'browser token rejected'
                }
            }

            Connect-HydrationGraphViaBrowser -TenantId '12345678-1234-1234-1234-123456789abc' -Scopes @('User.Read') -Environment Global

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
    }
}
