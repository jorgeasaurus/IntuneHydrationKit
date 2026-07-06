#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Groups/Invoke-GroupBatchImport.ps1
    . $PSScriptRoot/../../Private/Hydration/New-HydrationResult.ps1
    . $PSScriptRoot/../../Private/Hydration/New-HydrationDescription.ps1
    . $PSScriptRoot/../../Private/Groups/ConvertTo-HydrationGroupBody.ps1
    . $PSScriptRoot/../../Private/Groups/Get-HydrationGroupBatchResponses.ps1
    . $PSScriptRoot/../../Private/Groups/Get-HydrationGroupLookupUri.ps1
    . $PSScriptRoot/../../Private/Groups/New-HydrationBatchCorrelationFailure.ps1
    . $PSScriptRoot/../../Private/Groups/New-HydrationGroupMailNickname.ps1
    . $PSScriptRoot/../../Private/Groups/Resolve-HydrationIndeterminateGroupCreate.ps1
    . $PSScriptRoot/../../Private/Groups/Resolve-HydrationMissingGroupExistence.ps1
    . $PSScriptRoot/../../Private/Groups/Select-HydrationGroupLookupMatch.ps1
    . $PSScriptRoot/../../Private/Hydration/Get-HydrationMarkerSet.ps1
    . $PSScriptRoot/../../Private/Graph/Get-GraphErrorMessage.ps1
    . $PSScriptRoot/../../Private/Graph/Get-GraphStatusCode.ps1
    . $PSScriptRoot/../../Private/Graph/Get-HydrationBatchRetryAfterSeconds.ps1
    . $PSScriptRoot/../../Private/Graph/Invoke-GraphBatchOperation.ps1
    . $PSScriptRoot/../../Private/Graph/Resolve-HydrationBatchResponse.ps1
    . $PSScriptRoot/../../Private/Graph/Test-HydrationBatchStatusRetryable.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationTemplateNameMatch.ps1
    . $PSScriptRoot/../../Private/Hydration/Select-HydrationExistingMatch.ps1
    . $PSScriptRoot/../../Private/Hydration/Resolve-HydrationDeleteDecision.ps1
    . $PSScriptRoot/../../Private/Hydration/Resolve-HydrationMarkedDeleteCandidate.ps1
    . $PSScriptRoot/../../Private/Graph/Get-GraphPagedResults.ps1
    . $PSScriptRoot/../../Private/Auth/Get-HydrationGraphEnvironmentInfo.ps1
    . $PSScriptRoot/../../Public/Logging/Write-HydrationLog.ps1

    function Get-TestGroupNameSet {
        param(
            [Parameter(Mandatory)]
            [string[]]$Name
        )

        $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($currentName in $Name) {
            [void]$names.Add($currentName)
        }
        return $names
    }
}

Describe 'Invoke-GroupBatchImport delete mode' {
    BeforeEach {
        Mock Get-MgContext {
            return @{
                Environment = 'Global'
                TenantId    = '00000000-0000-0000-0000-000000000000'
            }
        }
        Mock Start-Sleep {}
        Mock Write-HydrationLog {}
    }

    It 'Should return empty result when no groups found to delete' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{ value = @() }
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name 'Hydration Group')

        $result | Should -BeNullOrEmpty
    }

    It 'Should only delete groups with hydration kit marker' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{
                value = @(
                    @{ id = 'id-1'; displayName = 'Hydration Group'; description = 'Test - Imported by Intune Hydration Kit' }
                    @{ id = 'id-2'; displayName = 'Other Group'; description = 'Not created by kit' }
                )
            }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
            return @{
                responses = @(
                    @{ id = '1'; status = 204 }
                )
            }
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name 'Hydration Group')

        $result | Should -HaveCount 1
        $result[0].Name | Should -Be 'Hydration Group'
        $result[0].Action | Should -Be 'Deleted'
    }

    It 'Should return WouldDelete action in WhatIf mode' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{
                value = @(
                    @{ id = 'id-1'; displayName = 'Test Group'; description = 'Imported by Intune Hydration Kit' }
                )
            }
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name 'Test Group') -WhatIf

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'WouldDelete'
        $result[0].Status | Should -Be 'DryRun'
    }

    It 'Should not emit built-in WhatIf output in delete mode' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{
                value = @(
                    @{ id = 'id-1'; displayName = 'Test Group'; description = 'Imported by Intune Hydration Kit' }
                )
            }
        }

        $stream = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name 'Test Group') -WhatIf 6>&1

        @($stream | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count | Should -Be 0
    }

    It 'Should delete all groups when batching' {
        $groups = 1..25 | ForEach-Object {
            @{ id = "id-$_"; displayName = "Group $_"; description = 'Imported by Intune Hydration Kit' }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{ value = $groups }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
            param($Body)
            $responses = $Body.requests | ForEach-Object {
                @{ id = $_.id; status = 204 }
            }
            return @{ responses = $responses }
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name (1..25 | ForEach-Object { "Group $_" }))

        $result | Should -HaveCount 25
        ($result | Where-Object { $_.Action -eq 'Deleted' }).Count | Should -Be 25
    }

    It 'Should retry missing batch delete responses through the batch executor' {
        $script:deleteBatchCallCount = 0
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{
                value = @(
                    @{ id = 'id-1'; displayName = 'Group 1'; description = 'Imported by Intune Hydration Kit' }
                    @{ id = 'id-2'; displayName = 'Group 2'; description = 'Imported by Intune Hydration Kit' }
                )
            }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
            $script:deleteBatchCallCount++
            if ($script:deleteBatchCallCount -eq 1) {
                return @{
                    responses = @(
                        @{ id = '1'; status = 204 }
                    )
                }
            }

            return @{
                responses = @(
                    @{ id = '1'; status = 204 }
                )
            }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq 'beta/groups/id-2' } {
            throw 'Direct delete retry should not be called'
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name @('Group 1', 'Group 2'))

        $result | Should -HaveCount 2
        ($result | Where-Object { $_.Action -eq 'Deleted' }).Count | Should -Be 2
        $script:deleteBatchCallCount | Should -Be 2
        Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq 'beta/groups/id-2' } -Times 0
    }

    It 'Should retry throttled batch delete responses' {
        $script:deleteBatchCallCount = 0
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{
                value = @(
                    @{ id = 'id-1'; displayName = 'Test Group'; description = 'Imported by Intune Hydration Kit' }
                )
            }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
            $script:deleteBatchCallCount++
            if ($script:deleteBatchCallCount -eq 1) {
                return @{
                    responses = @(
                        @{ id = '1'; status = 429; headers = @{ 'Retry-After' = '4' }; body = @{ error = @{ message = 'Too Many Requests' } } }
                    )
                }
            }

            return @{
                responses = @(
                    @{ id = '1'; status = 204 }
                )
            }
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name 'Test Group')

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Deleted'
        $script:deleteBatchCallCount | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -Scope It -ParameterFilter { $Seconds -eq 4 }
    }

    It 'Should handle 404 response as already deleted' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{
                value = @(
                    @{ id = 'id-1'; displayName = 'Test Group'; description = 'Imported by Intune Hydration Kit' }
                )
            }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
            return @{
                responses = @(
                    @{ id = '1'; status = 404; body = @{ error = @{ message = 'Not Found' } } }
                )
            }
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name 'Test Group')

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Skipped'
        $result[0].Status | Should -BeLike '*Already deleted*'
    }

    It 'Should handle delete failures' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
            return @{
                value = @(
                    @{ id = 'id-1'; displayName = 'Test Group'; description = 'Imported by Intune Hydration Kit' }
                )
            }
        }

        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
            return @{
                responses = @(
                    @{ id = '1'; status = 403; body = @{ error = @{ message = 'Access Denied' } } }
                )
            }
        }

        $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -KnownNames (Get-TestGroupNameSet -Name 'Test Group')

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Failed'
        $result[0].Status | Should -BeLike '*Delete failed*'
    }

    It 'Should use correct filter for Dynamic groups' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like "*groupTypes/any*" } {
            return @{ value = @() }
        }

        Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete

        Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like "*groupTypes/any(c:c eq 'DynamicMembership')*" } -Times 1
    }

    It 'Should use correct filter for Static groups' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like "*NOT groupTypes*" } {
            return @{ value = @() }
        }

        Invoke-GroupBatchImport -GroupType 'Static' -Delete

        Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like "*NOT groupTypes/any(c:c eq 'DynamicMembership')*" } -Times 1
    }
}
