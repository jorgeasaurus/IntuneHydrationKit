#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Graph/Get-GraphStatusCode.ps1
    . $PSScriptRoot/../../Private/Graph/Invoke-HydrationGraphRequest.ps1
}

Describe 'Invoke-HydrationGraphRequest' {
    BeforeAll {
        $script:GraphEndpoint = 'https://graph.microsoft.us'
        Mock Start-Sleep {}
    }

    Context 'URI normalization' {
        It 'Should trim the configured Graph endpoint from absolute URIs' {
            Mock Invoke-MgGraphRequest { @{ ok = $true } }

            $null = Invoke-HydrationGraphRequest -Method GET -Uri 'https://graph.microsoft.us/beta/deviceAppManagement/mobileApps'

            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Uri -eq 'beta/deviceAppManagement/mobileApps'
            }
        }

        It 'Should preserve relative URIs' {
            Mock Invoke-MgGraphRequest { @{ ok = $true } }

            $null = Invoke-HydrationGraphRequest -Method GET -Uri 'beta/deviceAppManagement/mobileApps'

            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Uri -eq 'beta/deviceAppManagement/mobileApps'
            }
        }
    }

    Context 'Body handling' {
        It 'Should pass JSON strings with content type through unchanged' {
            Mock Invoke-MgGraphRequest { @{ ok = $true } }

            $null = Invoke-HydrationGraphRequest -Method POST -Uri 'beta/deviceAppManagement/mobileApps' -Body '{"displayName":"Test"}'

            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Body -eq '{"displayName":"Test"}' -and $ContentType -eq 'application/json'
            }
        }
    }

    Context 'Retry behavior' {
        It 'Should retry transient server failures' {
            $script:attemptCount = 0
            Mock Invoke-MgGraphRequest {
                $script:attemptCount++
                if ($script:attemptCount -eq 1) {
                    $exception = [System.Exception]::new('Transient failure')
                    $exception | Add-Member -NotePropertyName 'ResponseStatusCode' -NotePropertyValue 503 -Force
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TransientFailure', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                    throw $errorRecord
                }

                return @{ id = 'success' }
            }

            $result = Invoke-HydrationGraphRequest -Method GET -Uri 'beta/deviceAppManagement/mobileApps' -RetryDelaySeconds 1

            $result.id | Should -Be 'success'
            $script:attemptCount | Should -Be 2
            Should -Invoke Start-Sleep -Exactly 1 -ParameterFilter { $Seconds -eq 1 }
        }

        It 'Should interpret MaxRetries as retries after the initial attempt' {
            $script:attemptCount = 0
            Mock Invoke-MgGraphRequest {
                $script:attemptCount++
                $exception = [System.Exception]::new('Transient failure')
                $exception | Add-Member -NotePropertyName 'ResponseStatusCode' -NotePropertyValue 503 -Force
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TransientFailure', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                throw $errorRecord
            }

            { Invoke-HydrationGraphRequest -Method GET -Uri 'beta/deviceAppManagement/mobileApps' -MaxRetries 1 -RetryDelaySeconds 1 } | Should -Throw

            $script:attemptCount | Should -Be 2
            Should -Invoke Start-Sleep -Exactly 1 -Scope It
        }

        It 'Should honor Retry-After headers when present' {
            $script:attemptCount = 0
            Mock Invoke-MgGraphRequest {
                $script:attemptCount++
                if ($script:attemptCount -eq 1) {
                    $exception = [System.Exception]::new('Too many requests')
                    $exception | Add-Member -NotePropertyName 'ResponseStatusCode' -NotePropertyValue 429 -Force
                    $exception | Add-Member -NotePropertyName 'ResponseHeaders' -NotePropertyValue @{ 'Retry-After' = '7' } -Force
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'Throttle', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
                    throw $errorRecord
                }

                return @{ id = 'success' }
            }

            $null = Invoke-HydrationGraphRequest -Method GET -Uri 'beta/deviceAppManagement/mobileApps'

            Should -Invoke Start-Sleep -Exactly 1 -ParameterFilter { $Seconds -eq 7 }
        }

        It 'Should rethrow non-retryable failures' {
            Mock Invoke-MgGraphRequest {
                $exception = [System.Exception]::new('Forbidden')
                $exception | Add-Member -NotePropertyName 'ResponseStatusCode' -NotePropertyValue 403 -Force
                $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'Forbidden', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
                throw $errorRecord
            }

            { Invoke-HydrationGraphRequest -Method GET -Uri 'beta/deviceAppManagement/mobileApps' } | Should -Throw
            Should -Invoke Start-Sleep -Exactly 0 -Scope It
        }

        It 'Should treat status code 0 as a resolved non-retryable status' {
            Mock Invoke-MgGraphRequest {
                $innerException = [System.Exception]::new('Nested retryable')
                $innerException | Add-Member -NotePropertyName 'ResponseStatusCode' -NotePropertyValue 503 -Force
                $innerErrorRecord = [System.Management.Automation.ErrorRecord]::new($innerException, 'NestedRetryable', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)

                $outerException = [System.Exception]::new('Proxy status', $innerException)
                $zeroStatusException = [System.Exception]::new('Status zero')
                $zeroStatusException | Add-Member -NotePropertyName 'ResponseStatusCode' -NotePropertyValue 0 -Force
                $zeroStatusRecord = [System.Management.Automation.ErrorRecord]::new($zeroStatusException, 'StatusZero', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $outerException | Add-Member -NotePropertyName 'ErrorRecord' -NotePropertyValue $zeroStatusRecord -Force
                $innerException | Add-Member -NotePropertyName 'ErrorRecord' -NotePropertyValue $innerErrorRecord -Force

                throw [System.Management.Automation.ErrorRecord]::new($outerException, 'Outer', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            }

            { Invoke-HydrationGraphRequest -Method GET -Uri 'beta/deviceAppManagement/mobileApps' } | Should -Throw
            Should -Invoke Start-Sleep -Exactly 0 -Scope It
        }
    }
}
