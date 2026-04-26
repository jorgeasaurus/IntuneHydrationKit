#Requires -Modules Pester

BeforeAll {
    $statusFunctionPath = Join-Path $PSScriptRoot '..\..\Private\Get-GraphStatusCode.ps1'
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Get-GraphErrorMessage.ps1'
    . $statusFunctionPath
    . $functionPath
}

Describe 'Get-GraphErrorMessage' {
    Context 'Status code extraction' {
        It 'Should include HTTP status code in output' {
            $response = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]::NotFound }
            $exception = [System.Exception]::new('Not Found')
            $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue $response -Force
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"ResourceNotFound","message":"Resource not found"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -BeLike 'HTTP 404*'
        }

        It 'Should handle missing status code gracefully' {
            $exception = [System.Exception]::new('Some error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"BadRequest","message":"Invalid"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Not -BeLike 'HTTP*'
        }
    }

    Context 'Error code extraction via regex' {
        It 'Should extract error code from JSON error response' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"Forbidden","message":"Insufficient privileges"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'Access denied - check permissions'
        }
    }

    Context 'Detail message extraction and truncation' {
        It 'Should extract detail message from JSON' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"BadRequest","message":"The property displayName is required"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'Invalid request - The property displayName is required'
        }

        It 'Should truncate detail messages longer than 200 characters' {
            $longMessage = 'A' * 250
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = "{`"error`":{`"code`":`"BadRequest`",`"message`":`"$longMessage`"}}"
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -BeLike '*...'
        }
    }

    Context 'JSON string unescaping' {
        It 'Should unescape \r\n in JSON messages' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"BadRequest","message":"Line1\\r\\nLine2"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Not -Match '\\r\\n'
        }

        It 'Should unescape escaped quotes in JSON messages' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $jsonMsg = '{"error":{"code":"BadRequest","message":"Field \"name\" is invalid"}}'
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = $jsonMsg
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -BeLike '*"name"*'
        }
    }

    Context 'Nested JSON Message extraction' {
        It 'Should extract inner Message field from nested JSON' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"BadRequest","message":"{\"Message\":\"The actual inner error detail\"}"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -BeLike '*actual inner error*'
        }
    }

    Context 'Known error code mapping' -ForEach @(
        @{ Code = 'ResourceNotFound'; Expected = 'Resource not found (may have been deleted already)' }
        @{ Code = 'InternalServerError'; Expected = 'Server error - please retry' }
        @{ Code = 'Forbidden'; Expected = 'Access denied - check permissions' }
        @{ Code = 'Unauthorized'; Expected = 'Authentication failed - reconnect to Graph' }
        @{ Code = 'TooManyRequests'; Expected = 'Rate limited - please wait and retry' }
        @{ Code = 'ServiceUnavailable'; Expected = 'Service unavailable - please retry later' }
    ) {
        It 'Should map <Code> to known message' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = "{`"error`":{`"code`":`"$Code`",`"message`":`"$Code`"}}"
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be $Expected
        }
    }

    Context 'BadRequest with detail message' {
        It 'Should include detail in BadRequest when available' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"BadRequest","message":"Missing required field"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'Invalid request - Missing required field'
        }

        It 'Should use generic message for BadRequest without detail' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"BadRequest","message":"BadRequest"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'Invalid request - check template format'
        }
    }

    Context 'Default/fallback behavior' {
        It 'Should use error code and detail for unknown codes' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"CustomError","message":"Something went wrong"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'CustomError - Something went wrong'
        }

        It 'Should return just error code when detail matches code' {
            $exception = [System.Exception]::new('error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"CustomError","message":"CustomError"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'CustomError'
        }

        It 'Should truncate raw message longer than 100 characters when no JSON found' {
            $longMessage = 'X' * 150
            $exception = [System.Exception]::new($longMessage)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result.Length | Should -BeLessOrEqual 103
            $result | Should -BeLike '*...'
        }

        It 'Should return raw message when short and no JSON found' {
            $exception = [System.Exception]::new('Simple error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'Simple error'
        }
    }

    Context 'Output format' {
        It 'Should format as "HTTP {statusCode} - {cleanMessage}"' {
            $response = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]::Forbidden }
            $exception = [System.Exception]::new('Forbidden')
            $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue $response -Force
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"Forbidden","message":"Insufficient privileges"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'HTTP 403 - Access denied - check permissions'
        }
    }

    Context 'ErrorDetails vs Exception.Message fallback' {
        It 'Should use ErrorDetails.Message when available' {
            $exception = [System.Exception]::new('Exception message with no JSON')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)
            $errorRecord | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue ([PSCustomObject]@{
                    Message = '{"error":{"code":"ResourceNotFound","message":"Not found"}}'
                }) -Force

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'Resource not found (may have been deleted already)'
        }

        It 'Should fall back to Exception.Message when ErrorDetails is null' {
            $exception = [System.Exception]::new('Plain error text')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)

            $result = Get-GraphErrorMessage -ErrorRecord $errorRecord
            $result | Should -Be 'Plain error text'
        }
    }
}
