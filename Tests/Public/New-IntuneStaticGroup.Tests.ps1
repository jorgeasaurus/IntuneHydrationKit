#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    # Get reference to the module
    $script:TestModule = Get-Module -Name IntuneHydrationKit | Select-Object -First 1

    if (-not $script:TestModule) {
        throw "Failed to import IntuneHydrationKit module"
    }
}

Describe 'New-IntuneStaticGroup' {
    Context 'Parameter Validation' {
        It 'Should have mandatory DisplayName parameter' {
            $command = Get-Command New-IntuneStaticGroup
            $param = $command.Parameters['DisplayName']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([string])
            ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have RequiresServicePrincipalOwner switch parameter' {
            $command = Get-Command New-IntuneStaticGroup
            $param = $command.Parameters['RequiresServicePrincipalOwner']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should support ShouldProcess (WhatIf)' {
            $command = Get-Command New-IntuneStaticGroup
            $command.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }
    }

    Context 'When group already exists with prefixed name' {
        BeforeEach {
            Mock Get-GraphPagedResults {
                @(@{ id = 'existing-group-id'; displayName = '[IHD] Update Ring Pilot' })
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest { } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return Skipped result' {
            $result = New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Skipped'
            $result.Status | Should -BeLike '*already exists*'
        }

        It 'Should return existing group id' {
            $result = New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            $result.Id | Should -Be 'existing-group-id'
        }

        It 'Should not call Invoke-MgGraphRequest for group creation' {
            New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ModuleName IntuneHydrationKit
        }
    }

    Context 'When group already exists with unprefixed legacy name' {
        BeforeEach {
            Mock Get-GraphPagedResults {
                @(@{ id = 'legacy-group-id'; displayName = 'Update Ring Pilot'; description = 'Imported by Intune Hydration Kit' })
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest { } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return Skipped result for backward compatibility' {
            $result = New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Skipped'
            $result.Id | Should -Be 'legacy-group-id'
        }
    }

    Context 'When group does not exist' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                @{ id = 'new-group-id'; displayName = '[IHD] Update Ring Pilot' }
            } -ModuleName IntuneHydrationKit

            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should create the group and return Created result' {
            $result = New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Created'
            $result.Id | Should -Be 'new-group-id'
        }

        It 'Should call Invoke-MgGraphRequest with POST to v1.0 groups endpoint' {
            New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/groups'
            }
        }

        It 'Should include [IHD] prefix in displayName' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'POST' -and $Uri -eq 'v1.0/groups') {
                    $script:capturedBody = $Body
                }
                @{ id = 'new-group-id'; displayName = '[IHD] Update Ring Pilot' }
            } -ModuleName IntuneHydrationKit

            New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            $script:capturedBody.displayName | Should -Be '[IHD] Update Ring Pilot'
        }

        It 'Should include hydration kit marker in description' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'POST' -and $Uri -eq 'v1.0/groups') {
                    $script:capturedBody = $Body
                }
                @{ id = 'new-group-id'; displayName = '[IHD] Update Ring Pilot' }
            } -ModuleName IntuneHydrationKit

            New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            $script:capturedBody.description | Should -BeLike '*Imported by Intune Hydration Kit*'
        }

        It 'Should not include DynamicMembership in groupTypes' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'POST' -and $Uri -eq 'v1.0/groups') {
                    $script:capturedBody = $Body
                }
                @{ id = 'new-group-id'; displayName = '[IHD] Update Ring Pilot' }
            } -ModuleName IntuneHydrationKit

            New-IntuneStaticGroup -DisplayName 'Update Ring Pilot'

            $script:capturedBody.Keys | Should -Not -Contain 'groupTypes'
        }
    }

    Context 'With RequiresServicePrincipalOwner when group does not exist' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit

            # Track all Invoke-MgGraphRequest calls
            $script:graphCalls = @()
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                $script:graphCalls += @{ Method = $Method; Uri = $Uri; Body = $Body }

                # GET service principals
                if ($Method -eq 'GET' -and $Uri -like '*servicePrincipals*') {
                    return @{ value = @(@{ id = 'sp-id-123'; appId = 'f1346770-5b25-470b-88bd-d5744ab7952c' }) }
                }
                # POST create group
                if ($Method -eq 'POST' -and $Uri -eq 'v1.0/groups') {
                    return @{ id = 'new-group-id'; displayName = '[IHD] Autopilot Prep' }
                }
                # POST add owner
                if ($Method -eq 'POST' -and $Uri -like '*owners*') {
                    return $null
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should query for the Intune Provisioning Client service principal' {
            New-IntuneStaticGroup -DisplayName 'Autopilot Prep' -RequiresServicePrincipalOwner

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*servicePrincipals*'
            }
        }

        It 'Should add service principal as owner after group creation' {
            New-IntuneStaticGroup -DisplayName 'Autopilot Prep' -RequiresServicePrincipalOwner

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*owners*'
            }
        }

        It 'Should return Created result with service principal owner status' {
            $result = New-IntuneStaticGroup -DisplayName 'Autopilot Prep' -RequiresServicePrincipalOwner

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Created'
            $result.Status | Should -BeLike '*service principal*'
        }
    }

    Context 'When existing group needs service principal owner added' {
        BeforeEach {
            Mock Get-GraphPagedResults {
                @(@{ id = 'existing-group-id'; displayName = '[IHD] Autopilot Prep' })
            } -ModuleName IntuneHydrationKit

            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)

                # GET service principals
                if ($Method -eq 'GET' -and $Uri -like '*servicePrincipals*') {
                    return @{ value = @(@{ id = 'sp-id-123'; appId = 'f1346770-5b25-470b-88bd-d5744ab7952c' }) }
                }
                # POST add owner - succeeds (SP not already owner)
                if ($Method -eq 'POST' -and $Uri -like '*owners*') {
                    return $null
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return Updated result when adding SP owner to existing group' {
            $result = New-IntuneStaticGroup -DisplayName 'Autopilot Prep' -RequiresServicePrincipalOwner

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Updated'
            $result.Status | Should -BeLike '*service principal*'
        }

        It 'Should return existing group id' {
            $result = New-IntuneStaticGroup -DisplayName 'Autopilot Prep' -RequiresServicePrincipalOwner

            $result.Id | Should -Be 'existing-group-id'
        }
    }

    Context 'When existing group already has service principal owner' {
        BeforeEach {
            Mock Get-GraphPagedResults {
                @(@{ id = 'existing-group-id'; displayName = '[IHD] Autopilot Prep' })
            } -ModuleName IntuneHydrationKit

            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)

                # GET service principals
                if ($Method -eq 'GET' -and $Uri -like '*servicePrincipals*') {
                    return @{ value = @(@{ id = 'sp-id-123'; appId = 'f1346770-5b25-470b-88bd-d5744ab7952c' }) }
                }
                # POST add owner - fails because already exists
                if ($Method -eq 'POST' -and $Uri -like '*owners*') {
                    $exception = [System.Exception]::new("One or more added object references already exist")
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'OwnerAlreadyExists',
                        [System.Management.Automation.ErrorCategory]::ResourceExists,
                        $null
                    )
                    throw $errorRecord
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return Skipped result when SP is already owner' {
            $result = New-IntuneStaticGroup -DisplayName 'Autopilot Prep' -RequiresServicePrincipalOwner

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Skipped'
            $result.Status | Should -BeLike '*already exists*'
        }
    }

    Context 'WhatIf support' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit
            Mock Invoke-MgGraphRequest { } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate action without calling Graph API for group creation' {
            $result = New-IntuneStaticGroup -DisplayName 'Test Group' -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'WouldCreate'

            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/groups'
            }
        }
    }

    Context 'Error handling' {
        BeforeEach {
            Mock Get-GraphPagedResults { @() } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
            Mock Get-GraphErrorMessage { "HTTP 403 - Access denied" } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                throw "Graph API error: Forbidden"
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return Failed result when Graph API throws' {
            $result = New-IntuneStaticGroup -DisplayName 'Failing Group'

            $result | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be 'Failed'
        }

        It 'Should include error message in status via Get-GraphErrorMessage' {
            $result = New-IntuneStaticGroup -DisplayName 'Failing Group'

            $result.Status | Should -Not -BeNullOrEmpty
        }
    }
}
