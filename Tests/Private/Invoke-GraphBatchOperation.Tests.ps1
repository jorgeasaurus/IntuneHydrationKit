#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Invoke-GraphBatchOperation.ps1
    . $PSScriptRoot/../../Private/New-HydrationResult.ps1
    . $PSScriptRoot/../../Private/New-HydrationDescription.ps1
    . $PSScriptRoot/../../Public/Write-HydrationLog.ps1
}

Describe 'Invoke-GraphBatchOperation' {

    BeforeAll {
        # Default mocks — overridden per-context as needed
        Mock Write-HydrationLog {}
        Mock Start-Sleep {}
    }

    Context 'POST success' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'new-guid-1'; displayName = 'Item1' } }
                        @{ id = '2'; status = 200; body = @{ id = 'new-guid-2'; displayName = 'Item2' } }
                    )
                }
            }

            $items = @(
                @{ Name = 'Item1'; BodyJson = '{"displayName":"Item1"}' }
                @{ Name = 'Item2'; BodyJson = '{"displayName":"Item2"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should return Created results for each item' {
            $script:result.Count | Should -Be 2
            $script:result[0].Action | Should -Be 'Created'
            $script:result[1].Action | Should -Be 'Created'
        }

        It 'Should capture the returned id' {
            $script:result | Where-Object { $_.Name -eq 'Item1' } | ForEach-Object { $_.Id | Should -Be 'new-guid-1' }
            $script:result | Where-Object { $_.Name -eq 'Item2' } | ForEach-Object { $_.Id | Should -Be 'new-guid-2' }
        }

        It 'Should set Status to Success' {
            $script:result | ForEach-Object { $_.Status | Should -Be 'Success' }
        }
    }

    Context 'DELETE 204 success' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '1'; status = 204; body = $null }
                    )
                }
            }

            $items = @(
                @{ Name = 'DeleteMe'; Id = 'guid-to-delete' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'DELETE' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should return Deleted action' {
            $script:result.Count | Should -Be 1
            $script:result[0].Action | Should -Be 'Deleted'
        }

        It 'Should set Status to Success' {
            $script:result[0].Status | Should -Be 'Success'
        }
    }

    Context 'DELETE 404 maps to Skipped' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '1'; status = 404; body = @{ error = @{ message = 'Not found' } } }
                    )
                }
            }

            $items = @(
                @{ Name = 'AlreadyGone'; Id = 'missing-guid' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'DELETE' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should return Skipped action' {
            $script:result.Count | Should -Be 1
            $script:result[0].Action | Should -Be 'Skipped'
        }

        It 'Should set Status to Already deleted' {
            $script:result[0].Status | Should -Be 'Already deleted'
        }
    }

    Context 'POST 409 conflict maps to Skipped' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '1'; status = 409; body = @{ error = @{ message = 'Conflict' } } }
                    )
                }
            }

            $items = @(
                @{ Name = 'Existing'; BodyJson = '{"displayName":"Existing"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should return Skipped action' {
            $script:result.Count | Should -Be 1
            $script:result[0].Action | Should -Be 'Skipped'
        }

        It 'Should indicate race condition' {
            $script:result[0].Status | Should -BeLike '*race condition*'
        }
    }

    Context 'Retry on 5xx with eventual success' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 503; body = @{ error = @{ message = 'Service Unavailable' } } }
                        )
                    }
                } else {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'retry-guid'; displayName = 'RetryItem' } }
                        )
                    }
                }
            }

            $items = @(
                @{ Name = 'RetryItem'; BodyJson = '{"displayName":"RetryItem"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType' -MaxRetries 3 -RetryDelaySeconds 0
        }

        It 'Should eventually return Created' {
            $created = $script:result | Where-Object { $_.Action -eq 'Created' }
            $created | Should -Not -BeNullOrEmpty
            $created.Id | Should -Be 'retry-guid'
        }

        It 'Should have called Graph API twice' {
            $script:callCount | Should -Be 2
        }

        It 'Should have called Start-Sleep for the retry delay' {
            Should -Invoke Start-Sleep -Times 1 -Scope Context
        }
    }

    Context 'Retry on 429 throttle with Retry-After header' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 429; headers = @{ 'Retry-After' = '5' }; body = @{ error = @{ message = 'Too Many Requests' } } }
                        )
                    }
                } else {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'throttle-guid'; displayName = 'ThrottledItem' } }
                        )
                    }
                }
            }

            $items = @(
                @{ Name = 'ThrottledItem'; BodyJson = '{"displayName":"ThrottledItem"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType' -MaxRetries 3 -RetryDelaySeconds 1
        }

        It 'Should eventually succeed after 429 throttle' {
            $created = $script:result | Where-Object { $_.Action -eq 'Created' }
            $created | Should -Not -BeNullOrEmpty
            $created.Id | Should -Be 'throttle-guid'
        }

        It 'Should have called Graph API twice' {
            $script:callCount | Should -Be 2
        }

        It 'Should honor Retry-After delay value' {
            Should -Invoke Start-Sleep -Times 1 -Scope Context -ParameterFilter { $Seconds -eq 5 }
        }
    }

    Context 'DELETE retry exhaustion maps to Failed' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '1'; status = 500; body = @{ error = @{ message = 'Internal Server Error' } } }
                    )
                }
            }

            $items = @(
                @{ Name = 'FailItem'; Id = 'fail-guid' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'DELETE' -BaseUrl '/test/endpoint' -ResultType 'TestType' -MaxRetries 2 -RetryDelaySeconds 0
        }

        It 'Should return Failed after retries exhausted' {
            $failed = $script:result | Where-Object { $_.Action -eq 'Failed' }
            $failed | Should -Not -BeNullOrEmpty
        }

        It 'Should include error message in status' {
            $failed = $script:result | Where-Object { $_.Action -eq 'Failed' }
            $failed.Status | Should -BeLike '*Internal Server Error*'
        }
    }

    Context 'Response id out of bounds maps to Failed' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '99'; status = 201; body = @{ id = 'oob-guid' } }
                    )
                }
            }

            $items = @(
                @{ Name = 'OnlyItem'; BodyJson = '{"displayName":"OnlyItem"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should return a Failed result for unmatched response' {
            $failed = $script:result | Where-Object { $_.Action -eq 'Failed' }
            $failed | Should -Not -BeNullOrEmpty
            # Out-of-bounds response ID generates an unmatched error
            $unmatched = $failed | Where-Object { $_.Status -like '*Unmatched batch response*' }
            $unmatched | Should -Not -BeNullOrEmpty
            # The actual item with no matching response is marked as missing
            $missing = $failed | Where-Object { $_.Status -like '*No response received*' }
            $missing | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Empty responses array maps to Failed' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @()
                }
            }

            $items = @(
                @{ Name = 'Item1'; BodyJson = '{"displayName":"Item1"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should return Failed for all items' {
            $script:result.Count | Should -Be 1
            $script:result[0].Action | Should -Be 'Failed'
        }

        It 'Should indicate missing responses' {
            $script:result[0].Status | Should -BeLike '*missing responses*'
        }
    }

    Context 'Missing responses property maps to Failed' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{}
            }

            $items = @(
                @{ Name = 'Item1'; Id = 'guid-1' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'DELETE' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should return Failed' {
            $script:result.Count | Should -Be 1
            $script:result[0].Action | Should -Be 'Failed'
        }
    }

    Context 'Empty items array' {
        It 'Should reject empty collection via parameter validation' {
            { Invoke-GraphBatchOperation -Items @() -Operation 'POST' -BaseUrl '/test' -ResultType 'Test' } | Should -Throw
        }
    }

    Context 'POST with missing BaseUrl and no item Url maps to Failed' {
        BeforeAll {
            $items = @(
                @{ Name = 'NoUrl'; BodyJson = '{"displayName":"NoUrl"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '' -ResultType 'TestType'
        }

        It 'Should return Failed with URL error' {
            $script:result.Count | Should -Be 1
            $script:result[0].Action | Should -Be 'Failed'
            $script:result[0].Status | Should -BeLike '*No API endpoint*'
        }
    }

    Context 'Per-item Url override' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '1'; status = 204; body = $null }
                    )
                }
            }

            $items = @(
                @{ Name = 'CustomUrl'; Id = 'guid-1'; Url = '/custom/path/guid-1' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'DELETE' -ResultType 'TestType'
        }

        It 'Should succeed using custom URL' {
            $script:result.Count | Should -Be 1
            $script:result[0].Action | Should -Be 'Deleted'
        }
    }

    Context 'Item Type override' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'typed-guid' } }
                    )
                }
            }

            $items = @(
                @{ Name = 'TypedItem'; BodyJson = '{"displayName":"TypedItem"}'; Type = 'CustomType' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test' -ResultType 'DefaultType'
        }

        It 'Should use per-item Type override' {
            $script:result[0].Type | Should -Be 'CustomType'
        }
    }
}
