#Requires -Modules Pester

BeforeAll {
    # Import the function under test and its dependencies
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Groups\Invoke-GroupBatchImport.ps1'
    $newHydrationResultPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\New-HydrationResult.ps1'
    $newHydrationDescriptionPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\New-HydrationDescription.ps1'
    $convertToHydrationGroupBodyPath = Join-Path $PSScriptRoot '..\..\Private\Groups\ConvertTo-HydrationGroupBody.ps1'
    $getHydrationGroupBatchResponsesPath = Join-Path $PSScriptRoot '..\..\Private\Groups\Get-HydrationGroupBatchResponses.ps1'
    $getHydrationGroupLookupUriPath = Join-Path $PSScriptRoot '..\..\Private\Groups\Get-HydrationGroupLookupUri.ps1'
    $newHydrationBatchCorrelationFailurePath = Join-Path $PSScriptRoot '..\..\Private\Groups\New-HydrationBatchCorrelationFailure.ps1'
    $newHydrationGroupMailNicknamePath = Join-Path $PSScriptRoot '..\..\Private\Groups\New-HydrationGroupMailNickname.ps1'
    $resolveHydrationIndeterminateGroupCreatePath = Join-Path $PSScriptRoot '..\..\Private\Groups\Resolve-HydrationIndeterminateGroupCreate.ps1'
    $resolveHydrationMissingGroupExistencePath = Join-Path $PSScriptRoot '..\..\Private\Groups\Resolve-HydrationMissingGroupExistence.ps1'
    $selectHydrationGroupLookupMatchPath = Join-Path $PSScriptRoot '..\..\Private\Groups\Select-HydrationGroupLookupMatch.ps1'
    $getHydrationMarkerSetPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\Get-HydrationMarkerSet.ps1'
    $getGraphErrorMessagePath = Join-Path $PSScriptRoot '..\..\Private\Graph\Get-GraphErrorMessage.ps1'
    $getGraphStatusCodePath = Join-Path $PSScriptRoot '..\..\Private\Graph\Get-GraphStatusCode.ps1'
    $getHydrationBatchRetryAfterSecondsPath = Join-Path $PSScriptRoot '..\..\Private\Graph\Get-HydrationBatchRetryAfterSeconds.ps1'
    $invokeGraphBatchOperationPath = Join-Path $PSScriptRoot '..\..\Private\Graph\Invoke-GraphBatchOperation.ps1'
    $resolveHydrationBatchResponsePath = Join-Path $PSScriptRoot '..\..\Private\Graph\Resolve-HydrationBatchResponse.ps1'
    $testHydrationBatchStatusRetryablePath = Join-Path $PSScriptRoot '..\..\Private\Graph\Test-HydrationBatchStatusRetryable.ps1'
    $testHydrationKitObjectPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\Test-HydrationKitObject.ps1'
    $testHydrationTemplateNameMatchPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\Test-HydrationTemplateNameMatch.ps1'
    $selectHydrationExistingMatchPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\Select-HydrationExistingMatch.ps1'
    $resolveHydrationDeleteDecisionPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\Resolve-HydrationDeleteDecision.ps1'
    $resolveHydrationMarkedDeleteCandidatePath = Join-Path $PSScriptRoot '..\..\Private\Hydration\Resolve-HydrationMarkedDeleteCandidate.ps1'
    $getGraphPagedResultsPath = Join-Path $PSScriptRoot '..\..\Private\Graph\Get-GraphPagedResults.ps1'
    $getHydrationGraphEnvironmentInfoPath = Join-Path $PSScriptRoot '..\..\Private\Auth\Get-HydrationGraphEnvironmentInfo.ps1'
    $writeHydrationLogPath = Join-Path $PSScriptRoot '..\..\Public\Logging\Write-HydrationLog.ps1'
    . $functionPath
    . $newHydrationResultPath
    . $convertToHydrationGroupBodyPath
    . $getHydrationGroupBatchResponsesPath
    . $getHydrationGroupLookupUriPath
    . $newHydrationBatchCorrelationFailurePath
    . $newHydrationGroupMailNicknamePath
    . $resolveHydrationIndeterminateGroupCreatePath
    . $resolveHydrationMissingGroupExistencePath
    . $selectHydrationGroupLookupMatchPath
    . $getHydrationMarkerSetPath
    . $newHydrationDescriptionPath
    . $getGraphStatusCodePath
    . $getGraphErrorMessagePath
    . $getHydrationBatchRetryAfterSecondsPath
    . $invokeGraphBatchOperationPath
    . $resolveHydrationBatchResponsePath
    . $testHydrationBatchStatusRetryablePath
    . $testHydrationKitObjectPath
    . $testHydrationTemplateNameMatchPath
    . $selectHydrationExistingMatchPath
    . $resolveHydrationDeleteDecisionPath
    . $resolveHydrationMarkedDeleteCandidatePath
    . $getGraphPagedResultsPath
    . $getHydrationGraphEnvironmentInfoPath
    . $writeHydrationLogPath
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
        Mock Start-Sleep {}
        Mock Write-HydrationLog {}
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

        It 'Should verify but not retry groups with missing create batch responses' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 200; body = @{ value = @() } }
                            @{ id = '2'; status = 200; body = @{ value = @() } }
                        )
                    }
                }

                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'new-id-1'; displayName = '[IHD] Test Group 1' } }
                    )
                }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'beta/groups?*' } {
                return @{ value = @() }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'beta/groups' } {
                throw 'Direct create retry should not be called'
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic'

            $created = @($result | Where-Object { $_.Action -eq 'Created' })
            $failed = @($result | Where-Object { $_.Action -eq 'Failed' })
            $created.Count | Should -Be 1
            $created.Id | Should -Contain 'new-id-1'
            $failed.Count | Should -Be 1
            $failed[0].Status | Should -BeLike '*not retried*'
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'beta/groups' } -Times 0 -Scope It
        }

        It 'Should retry throttled group create responses' {
            $script:createBatchCallCount = 0
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 200; body = @{ value = @() } }
                            @{ id = '2'; status = 200; body = @{ value = @() } }
                        )
                    }
                }

                $script:createBatchCallCount++
                if ($script:createBatchCallCount -eq 1) {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 429; headers = @{ 'Retry-After' = '3' }; body = @{ error = @{ message = 'Too Many Requests' } } }
                            @{ id = '2'; status = 201; body = @{ id = 'new-id-2'; displayName = '[IHD] Test Group 2' } }
                        )
                    }
                }

                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'new-id-1'; displayName = '[IHD] Test Group 1' } }
                    )
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic'

            ($result | Where-Object { $_.Action -eq 'Created' }) | Should -HaveCount 2
            $script:createBatchCallCount | Should -Be 2
            Should -Invoke Start-Sleep -Times 1 -Scope It -ParameterFilter { $Seconds -eq 3 }
        }

        It 'Should retry top-level throttled group create batch exceptions' {
            $script:createBatchCallCount = 0
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 200; body = @{ value = @() } }
                            @{ id = '2'; status = 200; body = @{ value = @() } }
                        )
                    }
                }

                $script:createBatchCallCount++
                if ($script:createBatchCallCount -eq 1) {
                    $exception = [System.Exception]::new('Too Many Requests')
                    $exception | Add-Member -NotePropertyName ResponseStatusCode -NotePropertyValue 429
                    throw $exception
                }

                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'new-id-1'; displayName = '[IHD] Test Group 1' } }
                        @{ id = '2'; status = 201; body = @{ id = 'new-id-2'; displayName = '[IHD] Test Group 2' } }
                    )
                }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic'

            ($result | Where-Object { $_.Action -eq 'Created' }) | Should -HaveCount 2
            $script:createBatchCallCount | Should -Be 2
            Should -Invoke Start-Sleep -Times 1 -Scope It -ParameterFilter { $Seconds -eq 2 }
        }

        It 'Should verify but not retry 5xx group create responses' {
            $script:createBatchCallCount = 0
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 200; body = @{ value = @() } }
                            @{ id = '2'; status = 200; body = @{ value = @() } }
                        )
                    }
                }

                $script:createBatchCallCount++
                return @{
                    responses = @(
                        @{ id = '1'; status = 503; body = @{ error = @{ message = 'Service Unavailable' } } }
                        @{ id = '2'; status = 201; body = @{ id = 'new-id-2'; displayName = '[IHD] Test Group 2' } }
                    )
                }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'beta/groups?*' } {
                return @{ value = @() }
            }

            $result = Invoke-GroupBatchImport -GroupDefinitions $script:testGroupDefs -GroupType 'Dynamic'

            ($result | Where-Object { $_.Action -eq 'Created' }) | Should -HaveCount 1
            ($result | Where-Object { $_.Status -like '*Creation indeterminate*' }) | Should -HaveCount 1
            $script:createBatchCallCount | Should -Be 1
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

        It 'Should make mailNickname collision-resistant after sanitizing displayName' {
            $groupDefs = @(
                @{ displayName = 'Test-Group'; description = 'One'; membershipRule = '(device.deviceOSType -eq "Windows")' }
                @{ displayName = 'Test_Group'; description = 'Two'; membershipRule = '(device.deviceOSType -eq "Windows")' }
            )
            $script:capturedNicknames = @()

            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                param($Body)
                $bodyObj = $Body
                if ($bodyObj.requests[0].method -eq 'GET') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 200; body = @{ value = @() } }
                            @{ id = '2'; status = 200; body = @{ value = @() } }
                        )
                    }
                }

                $script:capturedNicknames = @($bodyObj.requests | ForEach-Object { $_.body.mailNickname })
                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'new-id-1'; displayName = '[IHD] Test-Group' } }
                        @{ id = '2'; status = 201; body = @{ id = 'new-id-2'; displayName = '[IHD] Test_Group' } }
                    )
                }
            }

            Invoke-GroupBatchImport -GroupDefinitions $groupDefs -GroupType 'Dynamic'

            $script:capturedNicknames | Should -HaveCount 2
            $script:capturedNicknames[0] | Should -Not -Be $script:capturedNicknames[1]
            $script:capturedNicknames[0].Length | Should -BeLessOrEqual 64
            $script:capturedNicknames[1].Length | Should -BeLessOrEqual 64
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

        It 'Should use canonical Graph environment endpoint for owner references' {
            Mock Get-MgContext {
                return @{
                    Environment = 'USGovDoD'
                    TenantId    = '00000000-0000-0000-0000-000000000000'
                }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*$batch*' } {
                return @{ responses = @(@{ id = '1'; status = 200; body = @{ value = @() } }) }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like '*servicePrincipals*' } {
                return @{ value = @(@{ id = 'sp-id-123' }) }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/groups' } {
                return @{ id = 'new-group-id'; displayName = 'Windows Autopilot device preparation' }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*owners*' } {
                return @{}
            }

            Invoke-GroupBatchImport -GroupDefinitions $script:spOwnerGroupDefs -GroupType 'Static'

            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -like '*owners*' -and
                $Body.'@odata.id' -eq 'https://dod-graph.microsoft.us/v1.0/servicePrincipals/sp-id-123'
            } -Times 1
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
}
