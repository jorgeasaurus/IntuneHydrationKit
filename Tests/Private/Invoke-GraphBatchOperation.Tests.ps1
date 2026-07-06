#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Graph/Invoke-GraphBatchOperation.ps1
    . $PSScriptRoot/../../Private/Graph/Get-GraphStatusCode.ps1
    . $PSScriptRoot/../../Private/Graph/Get-HydrationBatchRetryAfterSeconds.ps1
    . $PSScriptRoot/../../Private/Graph/Resolve-HydrationBatchResponse.ps1
    . $PSScriptRoot/../../Private/Graph/Test-HydrationBatchStatusRetryable.ps1
    . $PSScriptRoot/../../Private/Hydration/New-HydrationResult.ps1
    . $PSScriptRoot/../../Private/Hydration/New-HydrationDescription.ps1
    . $PSScriptRoot/../../Public/Logging/Write-HydrationLog.ps1
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

    Context 'POST 5xx maps to indeterminate failed without retry' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                return @{
                    responses = @(
                        @{ id = '1'; status = 503; body = @{ error = @{ message = 'Service Unavailable' } } }
                    )
                }
            }

            $items = @(
                @{ Name = 'RetryItem'; BodyJson = '{"displayName":"RetryItem"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType' -MaxRetries 3 -RetryDelaySeconds 0
        }

        It 'Should return indeterminate failed' {
            $script:result | Should -HaveCount 1
            $script:result[0].Action | Should -Be 'Failed'
            $script:result[0].Status | Should -BeLike '*Create indeterminate*'
            $script:result[0].Status | Should -BeLike '*not retried*'
        }

        It 'Should call Graph API once' {
            $script:callCount | Should -Be 1
        }

        It 'Should not sleep for a retry delay' {
            Should -Invoke Start-Sleep -Times 0 -Scope Context
        }
    }

    Context 'DELETE retries 5xx with eventual success' {
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
                }

                return @{
                    responses = @(
                        @{ id = '1'; status = 204; body = $null }
                    )
                }
            }

            $items = @(
                @{ Name = 'RetryDeleteItem'; Id = 'delete-guid' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'DELETE' -BaseUrl '/test/endpoint' -ResultType 'TestType' -MaxRetries 3 -RetryDelaySeconds 0
        }

        It 'Should eventually return Deleted' {
            $script:result | Should -HaveCount 1
            $script:result[0].Action | Should -Be 'Deleted'
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

    Context 'Retry on top-level POST batch 429 exception' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $exception = [System.Exception]::new('Too Many Requests')
                    $exception | Add-Member -NotePropertyName ResponseStatusCode -NotePropertyValue 429
                    throw $exception
                }

                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'retry-guid'; displayName = 'TopLevelThrottledItem' } }
                    )
                }
            }

            $items = @(
                @{ Name = 'TopLevelThrottledItem'; BodyJson = '{"displayName":"TopLevelThrottledItem"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType' -MaxRetries 3 -RetryDelaySeconds 1
        }

        It 'Should eventually succeed after top-level 429 throttle' {
            $script:result | Should -HaveCount 1
            $script:result[0].Action | Should -Be 'Created'
            $script:result[0].Id | Should -Be 'retry-guid'
        }

        It 'Should retry the throttled batch once' {
            $script:callCount | Should -Be 2
            Should -Invoke Start-Sleep -Times 1 -Scope Context -ParameterFilter { $Seconds -eq 1 }
        }
    }

    Context 'Throttle-sensitive intent writes use longer retries without Retry-After header' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                if ($script:callCount -lt 3) {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 429; body = @{ error = @{ message = 'Too Many Requests' } } }
                        )
                    }
                }

                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'intent-guid'; displayName = 'IntentItem' } }
                    )
                }
            }

            $items = @(
                @{ Name = 'IntentItem'; Url = '/deviceManagement/intents'; BodyJson = '{"displayName":"IntentItem"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -ResultType 'TestType' -MaxRetries 1 -RetryDelaySeconds 1
        }

        It 'Should keep retrying throttled device intent writes beyond the default retry count' {
            $created = $script:result | Where-Object { $_.Action -eq 'Created' }
            $created | Should -Not -BeNullOrEmpty
            $created.Id | Should -Be 'intent-guid'
            $script:callCount | Should -Be 3
        }

        It 'Should use a longer fallback delay for device intent throttling' {
            Should -Invoke Start-Sleep -Times 1 -Scope Context -ParameterFilter { $Seconds -eq 15 }
            Should -Invoke Start-Sleep -Times 1 -Scope Context -ParameterFilter { $Seconds -eq 30 }
        }
    }

    Context 'POST whole-batch exception maps to indeterminate failed without retry' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                throw 'transport timeout'
            }

            $items = @(
                @{ Name = 'MaybeCreated1'; BodyJson = '{"displayName":"MaybeCreated1"}' }
                @{ Name = 'MaybeCreated2'; BodyJson = '{"displayName":"MaybeCreated2"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType' -MaxRetries 3 -RetryDelaySeconds 0
        }

        It 'Should return indeterminate failed results for all items' {
            $script:result | Should -HaveCount 2
            $script:result | ForEach-Object {
                $_.Action | Should -Be 'Failed'
                $_.Status | Should -BeLike '*Create indeterminate*'
                $_.Status | Should -BeLike '*not retried*'
            }
        }

        It 'Should not retry the indeterminate POST batch' {
            $script:callCount | Should -Be 1
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

    Context 'POST missing batch response maps to Failed' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                return @{
                    responses = @(
                        @{ id = '1'; status = 201; body = @{ id = 'created-guid' } }
                    )
                }
            }

            $items = @(
                @{ Name = 'CreatedItem'; BodyJson = '{"displayName":"CreatedItem"}' }
                @{ Name = 'MissingItem'; BodyJson = '{"displayName":"MissingItem"}' }
            )

            $script:result = Invoke-GraphBatchOperation -Items $items -Operation 'POST' -BaseUrl '/test/endpoint' -ResultType 'TestType'
        }

        It 'Should create the matched item and fail the missing item' {
            $script:result | Should -HaveCount 2
            ($script:result | Where-Object { $_.Name -eq 'CreatedItem' }).Action | Should -Be 'Created'
            ($script:result | Where-Object { $_.Name -eq 'MissingItem' }).Action | Should -Be 'Failed'
            ($script:result | Where-Object { $_.Name -eq 'MissingItem' }).Status | Should -BeLike '*not retried*'
        }

        It 'Should not retry a missing POST response' {
            $script:callCount | Should -Be 1
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
            $script:result[0].Status | Should -BeLike '*indeterminate*'
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
