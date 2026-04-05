#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Test-ConditionalAccessPolicyRequiresP2.ps1'
    . $functionPath
}

Describe 'Test-ConditionalAccessPolicyRequiresP2' {
    Context 'signInRiskLevels' {
        It 'Should return $true when signInRiskLevels has items' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    signInRiskLevels = @('high', 'medium')
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeTrue
        }

        It 'Should return $false when signInRiskLevels is empty array' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    signInRiskLevels = @()
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }
    }

    Context 'userRiskLevels' {
        It 'Should return $true when userRiskLevels has items' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    userRiskLevels = @('high')
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeTrue
        }

        It 'Should return $false when userRiskLevels is empty array' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    userRiskLevels = @()
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }
    }

    Context 'insiderRiskLevels' {
        It 'Should return $true when insiderRiskLevels is a non-null string' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    insiderRiskLevels = 'elevated'
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeTrue
        }

        It 'Should return $false when insiderRiskLevels is "null" string' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    insiderRiskLevels = 'null'
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }

        It 'Should return $false when insiderRiskLevels is empty string' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    insiderRiskLevels = ''
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }
    }

    Context 'agentIdRiskLevels' {
        It 'Should return $true when agentIdRiskLevels is an array with items' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    agentIdRiskLevels = @('high')
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeTrue
        }

        It 'Should return $true when agentIdRiskLevels is a non-empty string' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    agentIdRiskLevels = 'high'
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeTrue
        }

        It 'Should return $false when agentIdRiskLevels is empty array' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    agentIdRiskLevels = @()
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }
    }

    Context 'servicePrincipalRiskLevels' {
        It 'Should return $true when servicePrincipalRiskLevels is an array with items' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    servicePrincipalRiskLevels = @('medium', 'high')
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeTrue
        }

        It 'Should return $true when servicePrincipalRiskLevels is a non-empty string' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    servicePrincipalRiskLevels = 'high'
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeTrue
        }

        It 'Should return $false when servicePrincipalRiskLevels is empty array' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    servicePrincipalRiskLevels = @()
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }
    }

    Context 'No conditions or no risk levels' {
        It 'Should return $false when conditions is missing' {
            $policy = [PSCustomObject]@{ displayName = 'Basic Policy' }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }

        It 'Should return $false when no risk levels are set' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    applications = [PSCustomObject]@{ includeApplications = @('All') }
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }

        It 'Should return $false when all risk level arrays are empty' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    signInRiskLevels           = @()
                    userRiskLevels             = @()
                    agentIdRiskLevels          = @()
                    servicePrincipalRiskLevels = @()
                }
            }
            Test-ConditionalAccessPolicyRequiresP2 -Policy $policy | Should -BeFalse
        }
    }

    Context 'Return type' {
        It 'Should return a boolean' -TestCases @(
            @{
                Policy = [PSCustomObject]@{
                    conditions = [PSCustomObject]@{ signInRiskLevels = @('high') }
                }
                Expected = $true
            }
            @{
                Policy = [PSCustomObject]@{
                    conditions = [PSCustomObject]@{ signInRiskLevels = @() }
                }
                Expected = $false
            }
        ) {
            $result = Test-ConditionalAccessPolicyRequiresP2 -Policy $Policy
            $result | Should -BeOfType [bool]
            $result | Should -Be $Expected
        }
    }
}
