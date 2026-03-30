BeforeAll {
    . $PSScriptRoot/../../Private/Get-GraphPagedResults.ps1
}

Describe 'Get-GraphPagedResults' {
    BeforeAll {
        Mock Invoke-MgGraphRequest {}
    }

    Context 'When response is a single page' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                @{
                    value             = @(@{ id = '1'; displayName = 'Policy1' }, @{ id = '2'; displayName = 'Policy2' })
                    '@odata.nextLink' = $null
                }
            }
        }

        It 'Should return all items' {
            $result = Get-GraphPagedResults -Uri 'beta/test'
            $result.Count | Should -Be 2
            $result[0].displayName | Should -Be 'Policy1'
        }
    }

    Context 'When response has multiple pages' {
        BeforeAll {
            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    @{
                        value             = @(@{ id = '1' })
                        '@odata.nextLink' = 'https://graph.microsoft.com/beta/test?$skiptoken=abc'
                    }
                } else {
                    @{
                        value             = @(@{ id = '2' })
                        '@odata.nextLink' = $null
                    }
                }
            }
        }

        It 'Should follow nextLink and return all items' {
            $script:callCount = 0
            $result = Get-GraphPagedResults -Uri 'beta/test'
            $result.Count | Should -Be 2
            Should -Invoke Invoke-MgGraphRequest -Times 2
        }
    }

    Context 'When ProcessItems scriptblock is provided' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                @{
                    value             = @(@{ id = '1' }, @{ id = '2' })
                    '@odata.nextLink' = $null
                }
            }
        }

        It 'Should invoke the scriptblock with page items' {
            $collected = @()
            Get-GraphPagedResults -Uri 'beta/test' -ProcessItems {
                param($items)
                $collected += $items
            }.GetNewClosure()
            # ProcessItems mode does not return results
        }

        It 'Should not return results in ProcessItems mode' {
            $result = Get-GraphPagedResults -Uri 'beta/test' -ProcessItems { param($items) }
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When Headers are provided' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                @{ value = @(); '@odata.nextLink' = $null }
            }
        }

        It 'Should pass headers to Invoke-MgGraphRequest' {
            Get-GraphPagedResults -Uri 'beta/test' -Headers @{ ConsistencyLevel = 'eventual' }
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Headers -and $Headers['ConsistencyLevel'] -eq 'eventual'
            }
        }
    }

    Context 'When response has empty value array' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                @{ value = @(); '@odata.nextLink' = $null }
            }
        }

        It 'Should return empty array' {
            $result = Get-GraphPagedResults -Uri 'beta/test'
            $result | Should -HaveCount 0
        }
    }
}
