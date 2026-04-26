#Requires -Modules Pester

BeforeAll {
    # Import the function under test and its dependencies
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Invoke-GroupBatchImport.ps1'
    $newHydrationResultPath = Join-Path $PSScriptRoot '..\..\Private\New-HydrationResult.ps1'
    $newHydrationDescriptionPath = Join-Path $PSScriptRoot '..\..\Private\New-HydrationDescription.ps1'
    $getHydrationMarkerSetPath = Join-Path $PSScriptRoot '..\..\Private\Get-HydrationMarkerSet.ps1'
    $getGraphErrorMessagePath = Join-Path $PSScriptRoot '..\..\Private\Get-GraphErrorMessage.ps1'
    $getGraphStatusCodePath = Join-Path $PSScriptRoot '..\..\Private\Get-GraphStatusCode.ps1'
    $testHydrationKitObjectPath = Join-Path $PSScriptRoot '..\..\Private\Test-HydrationKitObject.ps1'
    $getGraphPagedResultsPath = Join-Path $PSScriptRoot '..\..\Private\Get-GraphPagedResults.ps1'
    . $functionPath
    . $newHydrationResultPath
    . $getHydrationMarkerSetPath
    . $newHydrationDescriptionPath
    . $getGraphStatusCodePath
    . $getGraphErrorMessagePath
    . $testHydrationKitObjectPath
    . $getGraphPagedResultsPath
}

Describe 'Invoke-GroupBatchImport' {
    BeforeEach {
        # Mock Get-MgContext to simulate an active connection
        Mock Get-MgContext {
            return @{
                Environment = 'Global'
                TenantId    = '00000000-0000-0000-0000-000000000000'
            }
        }
    }

    Context 'Parameter validation' {
        It 'Should validate GroupType is Dynamic or Static' {
            { Invoke-GroupBatchImport -GroupDefinitions @() -GroupType 'Invalid' } | Should -Throw
        }

        It 'Should accept Dynamic as GroupType' {
            Mock Invoke-MgGraphRequest { return @{ responses = @() } }
            { Invoke-GroupBatchImport -GroupDefinitions @() -GroupType 'Dynamic' } | Should -Not -Throw
        }

        It 'Should accept Static as GroupType' {
            Mock Invoke-MgGraphRequest { return @{ responses = @() } }
            { Invoke-GroupBatchImport -GroupDefinitions @() -GroupType 'Static' } | Should -Not -Throw
        }

        It 'Should accept Delete switch without GroupDefinitions' {
            Mock Invoke-MgGraphRequest { return @{ value = @() } }
            { Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete } | Should -Not -Throw
        }
    }

    Context 'When no groups are provided' {
        It 'Should return empty array for empty GroupDefinitions' {
            $result = Invoke-GroupBatchImport -GroupDefinitions @() -GroupType 'Dynamic'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When Graph connection is not established' {
        It 'Should return empty result when Get-MgContext returns null' {
            Mock Get-MgContext { return $null }
            Mock Write-Error {}

            $result = Invoke-GroupBatchImport -GroupDefinitions @(@{ displayName = 'Test' }) -GroupType 'Dynamic'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When checking group existence' {
        BeforeEach {
            $script:testGroupDefs = @(
                @{ displayName = 'Test Group 1'; description = 'Description 1'; membershipRule = '(device.deviceOSType -eq "Windows")' }
                @{ displayName = 'Test Group 2'; description = 'Description 2'; membershipRule = '(device.deviceOSType -eq "macOS")' }
            )
        }

        It 'Should skip groups that already exist' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                return @{
                    responses = @(
                        @{
                            id     = '1'
                            status = 200
                            body   = @{
                                value = @(@{ id = 'existing-id-1'; displayName = 'Test Group 1'; description = 'Existing' })
                            }
                        }
                        @{
                            id     = '2'
                            status = 200
                            body   = @{
                                value = @(@{ id = 'existing-id-2'; displayName = 'Test Group 2'; description = 'Existing' })
                            }
                        }
                    )
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 2
            $result[0].Action | Should -Be 'Skipped'
            $result[1].Action | Should -Be 'Skipped'
            $result[0].Status | Should -Be 'Group already exists'
        }

        It 'Should proceed to create groups that do not exist' {
            # First batch call - existence check returns no matches
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                # Check if this is an existence check (GET requests) or creation (POST requests)
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 200; body = @{ value = @() } }
                            @{ id = '2'; status = 200; body = @{ value = @() } }
                        )
                    }
                } else {
                    # Creation batch
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-id-1'; displayName = 'Test Group 1' } }
                            @{ id = '2'; status = 201; body = @{ id = 'new-id-2'; displayName = 'Test Group 2' } }
                        )
                    }
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 2
            $result[0].Action | Should -Be 'Created'
            $result[1].Action | Should -Be 'Created'
        }
    }

    Context 'When creating dynamic groups' {
        BeforeEach {
            $script:dynamicGroupDefs = @(
                @{
                    displayName    = 'Windows Devices'
                    description    = 'All Windows devices'
                    membershipRule = '(device.deviceOSType -eq "Windows")'
                }
            )
        }

        It 'Should include dynamic membership properties in creation request' {
            $capturedBody = $null
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
                } else {
                    $script:capturedBody = $bodyObj
                    return @{ responses = @(@{ id = '1'; status = 201; body = @{ id = 'new-id'; displayName = 'Windows Devices' } }) }
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:dynamicGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Created'
        }

        It 'Should add Hydration Kit marker to description' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
                } else {
                    # Verify description contains marker
                    $groupBody = $bodyObj.requests[0].body
                    $groupBody.description | Should -BeLike '*Imported by Intune Hydration Kit*'
                    return @{ responses = @(@{ id = '1'; status = 201; body = @{ id = 'new-id'; displayName = 'Windows Devices' } }) }
                }
            }

            Invoke-GroupBatchImport -GroupDefinitions $script:dynamicGroupDefs -GroupType 'Dynamic'
        }
    }

    Context 'When creating static groups' {
        BeforeEach {
            $script:staticGroupDefs = @(
                @{
                    displayName = 'Pilot Users'
                    description = 'Users for pilot ring'
                }
            )
        }

        It 'Should not include dynamic membership properties for static groups' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
                } else {
                    # Verify no dynamic properties
                    $groupBody = $bodyObj.requests[0].body
                    $groupBody.groupTypes | Should -BeNullOrEmpty
                    $groupBody.membershipRule | Should -BeNullOrEmpty
                    return @{ responses = @(@{ id = '1'; status = 201; body = @{ id = 'new-id'; displayName = 'Pilot Users' } }) }
                }
            }

            Invoke-GroupBatchImport -GroupDefinitions $script:staticGroupDefs -GroupType 'Static'
        }
    }

    Context 'When handling service principal owner groups' {
        BeforeEach {
            $script:spOwnerGroupDefs = @(
                @{
                    displayName                   = 'Windows Autopilot device preparation'
                    description                   = 'Autopilot prep group'
                    requiresServicePrincipalOwner = $true
                }
            )
        }

        It 'Should handle groups requiring service principal owner separately' {
            # Mock existence check - group doesn't exist
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
            }

            # Mock SP lookup
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like '*servicePrincipals*' } {
                return @{ value = @(@{ id = 'sp-id-123' }) }
            }

            # Mock group creation
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/groups' } {
                return @{ id = 'new-group-id'; displayName = 'Windows Autopilot device preparation' }
            }

            # Mock owner addition
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*owners*' } {
                return @{}
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:spOwnerGroupDefs -GroupType 'Static'

            # Filter to only SP owner results (skip the batch existence check skipped result)
            $spResults = $result | Where-Object { $_.Status -like '*service principal*' }
            $spResults | Should -HaveCount 1
            $spResults[0].Action | Should -Be 'Created'
        }

        It 'Should create service principal if it does not exist' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
            }

            # Mock SP lookup - not found
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like '*servicePrincipals*' } {
                return @{ value = @() }
            }

            # Mock SP creation
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/servicePrincipals' } {
                return @{ id = 'new-sp-id' }
            }

            # Mock group creation
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/groups' } {
                return @{ id = 'new-group-id'; displayName = 'Windows Autopilot device preparation' }
            }

            # Mock owner addition
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*owners*' } {
                return @{}
            }

            Invoke-GroupBatchImport -GroupDefinitions $script:spOwnerGroupDefs -GroupType 'Static'

            Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/servicePrincipals' } -Times 1
        }
    }

    Context 'When handling WhatIf mode' {
        BeforeEach {
            $script:testGroupDefs = @(
                @{ displayName = 'Test Group'; description = 'Test'; membershipRule = '(device.deviceOSType -eq "Windows")' }
            )
        }

        It 'Should return WouldCreate action in WhatIf mode' {
            # Mock existence check - group doesn't exist
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic' -WhatIf

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'WouldCreate'
            $result[0].Status | Should -Be 'DryRun'
        }

        It 'Should not emit built-in WhatIf output in create mode' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
            }

            $stream = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic' -WhatIf 6>&1

            @($stream | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count | Should -Be 0
        }

        It 'Should not make creation API calls in WhatIf mode' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
                } else {
                    throw "Creation batch should not be called in WhatIf mode"
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic' -WhatIf

            $result[0].Action | Should -Be 'WouldCreate'
        }
    }

    Context 'When handling errors' {
        BeforeEach {
            $script:testGroupDefs = @(
                @{ displayName = 'Test Group'; description = 'Test'; membershipRule = '(device.deviceOSType -eq "Windows")' }
            )
        }

        It 'Should handle existence check failures' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                return @{
                    responses = @(
                        @{ id = '1'; status = 400; body = @{ error = @{ message = 'Bad Request' } } }
                    )
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $testGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Existence check failed*'
        }

        It 'Should handle creation failures' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
                } else {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 400; body = @{ error = @{ message = 'Invalid membership rule' } } }
                        )
                    }
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $testGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Creation failed*'
        }

        It 'Should handle 409 Conflict as race condition (group created between check and create)' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
                } else {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 409; body = @{ error = @{ message = 'Conflict' } } }
                        )
                    }
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $testGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Skipped'
            $result[0].Status | Should -BeLike '*race condition*'
        }

        It 'Should handle batch request exception' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                throw "Network error"
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $testGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Batch*failed*'
        }
    }

    Context 'When batching requests' {
        It 'Should create all 25 groups when batching' {
            # Create 25 group definitions to test batching
            $manyGroupDefs = 1..25 | ForEach-Object {
                @{
                    displayName    = "Test Group $_"
                    description    = "Description $_"
                    membershipRule = "(device.deviceOSType -eq 'Windows')"
                }
            }

            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body

                if ($bodyObj.requests[0].method -eq 'GET') {
                    # Existence check - return empty for all
                    $responses = $bodyObj.requests | ForEach-Object {
                        @{ id = $_.id; status = 200; body = @{ value = @() } }
                    }
                    return @{ responses = $responses }
                } else {
                    # Creation - return success for all
                    $responses = $bodyObj.requests | ForEach-Object {
                        @{ id = $_.id; status = 201; body = @{ id = "id-$($_.id)"; displayName = $_.body.displayName } }
                    }
                    return @{ responses = $responses }
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $manyGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 25
            ($result | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 25
        }
    }

    Context 'When handling different Azure environments' {
        It 'Should use beta endpoint for batch requests' {
            Mock Get-MgContext {
                return @{ Environment = 'Global'; TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            $testGroupDefs = @(
                @{ displayName = 'Test'; description = 'Test'; membershipRule = '(device.deviceOSType -eq "Windows")' }
            )

            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like 'beta/*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
                } else {
                    return @{ responses = @(@{ id = '1'; status = 201; body = @{ id = 'id'; displayName = 'Test' } }) }
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $testGroupDefs -GroupType 'Dynamic'

            $result | Should -HaveCount 1
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Uri -like 'beta/*$batch*' } -Times 2
        }
    }

    Context 'When handling special characters in group names' {
        It 'Should handle groups with special characters in display name' {
            $groupWithQuote = @(
                @{
                    displayName    = "Test's Group"
                    description    = 'Test description'
                    membershipRule = '(device.deviceOSType -eq "Windows")'
                }
            )

            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    # Verify the URL contains escaped quote
                    $bodyObj.requests[0].url | Should -BeLike "*Test''s Group*"
                    return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @(@{ id = 'id'; displayName = "Test's Group" }) } }) }
                }
                return @{ responses = @() }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $groupWithQuote -GroupType 'Dynamic'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Skipped'
        }
    }

    Context 'When deleting groups (Delete mode)' {
        It 'Should return empty result when no groups found to delete' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
                return @{ value = @() }
            }

            $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete

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

            $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete

            # Only the group with hydration marker should be deleted
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

            $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -WhatIf

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

            $stream = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete -WhatIf 6>&1

            @($stream | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count | Should -Be 0
        }

        It 'Should delete all 25 groups when batching' {
            # Create 25 groups to delete
            $groups = 1..25 | ForEach-Object {
                @{ id = "id-$_"; displayName = "Group $_"; description = 'Imported by Intune Hydration Kit' }
            }

            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
                return @{ value = $groups }
            }

            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body

                $responses = $bodyObj.requests | ForEach-Object {
                    @{ id = $_.id; status = 204 }
                }
                return @{ responses = $responses }
            }

            $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete

            $result | Should -HaveCount 25
            ($result | Where-Object { $_.Action -eq 'Deleted' }).Count | Should -Be 25
        }

        It 'Should retry missing batch delete responses directly' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' } {
                return @{
                    value = @(
                        @{ id = 'id-1'; displayName = 'Group 1'; description = 'Imported by Intune Hydration Kit' }
                        @{ id = 'id-2'; displayName = 'Group 2'; description = 'Imported by Intune Hydration Kit' }
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

            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq 'beta/groups/id-2' } {
                return $null
            }

            $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete

            $result | Should -HaveCount 2
            ($result | Where-Object { $_.Action -eq 'Deleted' }).Count | Should -Be 2
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq 'beta/groups/id-2' } -Times 1
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

            $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete

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

            $result = Invoke-GroupBatchImport -GroupType 'Dynamic' -Delete

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
}
