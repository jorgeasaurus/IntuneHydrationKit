#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'New-IntuneDynamicGroup' {
    BeforeEach {
        Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
    }

    It 'Skips an existing dynamic group even when an incompatible same-named group is returned first' {
        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        id              = 'static-id'
                        displayName     = 'Shared Name'
                        securityEnabled = $true
                        groupTypes      = @()
                    },
                    @{
                        id              = 'dynamic-id'
                        displayName     = 'Shared Name'
                        securityEnabled = $true
                        groupTypes      = @('DynamicMembership')
                        membershipRule  = "(device.deviceOSType -eq 'Windows')"
                    }
                )
            }
        } -ModuleName IntuneHydrationKit

        $result = New-IntuneDynamicGroup -DisplayName 'Shared Name' -MembershipRule "(device.deviceOSType -eq 'Windows')"

        $result.Action | Should -Be 'Skipped'
        $result.Id | Should -Be 'dynamic-id'
        Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'Fails when only a non-dynamic same-named group exists' {
        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        id              = 'static-id'
                        displayName     = 'Shared Name'
                        securityEnabled = $true
                        groupTypes      = @()
                    }
                )
            }
        } -ModuleName IntuneHydrationKit

        $result = New-IntuneDynamicGroup -DisplayName 'Shared Name' -MembershipRule "(device.deviceOSType -eq 'Windows')" -WarningAction SilentlyContinue

        $result.Action | Should -Be 'Failed'
        $result.Status | Should -Be 'A non-dynamic group with this displayName already exists'
        Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'Warns and skips when an existing dynamic group has a different membership rule' {
        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        id              = 'dynamic-id'
                        displayName     = 'Shared Name'
                        securityEnabled = $true
                        groupTypes      = @('DynamicMembership')
                        membershipRule  = "(device.deviceOSType -eq 'iPad')"
                    }
                )
            }
        } -ModuleName IntuneHydrationKit

        $warnings = @()
        $result = New-IntuneDynamicGroup -DisplayName 'Shared Name' -MembershipRule "(device.deviceOSType -eq 'Windows')" -WarningVariable warnings -WarningAction SilentlyContinue

        $result.Action | Should -Be 'Skipped'
        $warnings[0] | Should -BeLike '*membership rule differs*'
    }

    It 'Creates with a safe fallback mailNickname when display name has no alphanumeric characters' {
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET') {
                return @{ value = @() }
            }

            return @{
                id          = 'new-id'
                displayName = $Body.displayName
            }
        } -ModuleName IntuneHydrationKit

        $result = New-IntuneDynamicGroup -DisplayName '!!!' -MembershipRule "(device.deviceOSType -eq 'Windows')"

        $result.Action | Should -Be 'Created'
        Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Exactly 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Body.mailNickname -match '^group[a-f0-9]{8}$' -and
            $Body.mailNickname.Length -le 64
        }
    }

    It 'Truncates generated mailNickname to Graph limit' {
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET') {
                return @{ value = @() }
            }

            return @{
                id          = 'new-id'
                displayName = $Body.displayName
            }
        } -ModuleName IntuneHydrationKit

        $displayName = 'A' * 80
        $result = New-IntuneDynamicGroup -DisplayName $displayName -MembershipRule "(device.deviceOSType -eq 'Windows')"

        $result.Action | Should -Be 'Created'
        Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -Exactly 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.mailNickname.Length -eq 64
        }
    }
}
