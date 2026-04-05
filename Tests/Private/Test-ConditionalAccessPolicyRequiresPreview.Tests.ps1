#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Test-ConditionalAccessPolicyRequiresPreview.ps1'
    . $functionPath
}

Describe 'Test-ConditionalAccessPolicyRequiresPreview' {
    Context 'AccountRecovery user action' {
        It 'Should return "AccountRecovery" when includeUserActions contains accountrecovery' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    applications = [PSCustomObject]@{
                        includeUserActions = @('urn:user:accountrecovery')
                    }
                }
            }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -Be 'AccountRecovery'
        }

        It 'Should return "AccountRecovery" when accountrecovery is among multiple actions' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    applications = [PSCustomObject]@{
                        includeUserActions = @(
                            'urn:user:registersecurityinfo',
                            'urn:user:accountrecovery'
                        )
                    }
                }
            }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -Be 'AccountRecovery'
        }
    }

    Context 'No preview features required' {
        It 'Should return $null when no user actions are defined' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    applications = [PSCustomObject]@{
                        includeApplications = @('All')
                    }
                }
            }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -BeNullOrEmpty
        }

        It 'Should return $null when user actions do not include accountrecovery' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    applications = [PSCustomObject]@{
                        includeUserActions = @('urn:user:registersecurityinfo')
                    }
                }
            }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -BeNullOrEmpty
        }

        It 'Should return $null when conditions is missing' {
            $policy = [PSCustomObject]@{ displayName = 'Simple Policy' }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -BeNullOrEmpty
        }

        It 'Should return $null when applications is missing from conditions' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    users = [PSCustomObject]@{ includeUsers = @('All') }
                }
            }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -BeNullOrEmpty
        }

        It 'Should return $null when includeUserActions is empty' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    applications = [PSCustomObject]@{
                        includeUserActions = @()
                    }
                }
            }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Return type' {
        It 'Should return a string when preview is required' {
            $policy = [PSCustomObject]@{
                conditions = [PSCustomObject]@{
                    applications = [PSCustomObject]@{
                        includeUserActions = @('urn:user:accountrecovery')
                    }
                }
            }
            $result = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            $result | Should -BeOfType [string]
        }
    }
}
