#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Hydration\New-HydrationResult.ps1'
    . $functionPath
}

Describe 'New-HydrationResult' {
    Context 'Required properties' {
        BeforeAll {
            $script:result = New-HydrationResult -Name 'Test Policy' -Action 'Created' -Status 'Success'
        }

        It 'Should have Name property' {
            $script:result.Name | Should -Be 'Test Policy'
        }

        It 'Should have Action property' {
            $script:result.Action | Should -Be 'Created'
        }

        It 'Should have Status property' {
            $script:result.Status | Should -Be 'Success'
        }

        It 'Should have Timestamp property' {
            $script:result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should have Timestamp in "yyyy-MM-dd HH:mm:ss" format' {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }

    Context 'Optional properties when provided' {
        BeforeAll {
            $script:result = New-HydrationResult -Name 'Test' -Action 'Created' -Status 'Success' `
                -Path '/templates/policy.json' -Type 'CompliancePolicy' `
                -Id 'abc-123' -Platform 'Windows' -State 'enabled'
        }

        It 'Should include Path when provided' {
            $script:result.Path | Should -Be '/templates/policy.json'
        }

        It 'Should include Type when provided' {
            $script:result.Type | Should -Be 'CompliancePolicy'
        }

        It 'Should include Id when provided' {
            $script:result.Id | Should -Be 'abc-123'
        }

        It 'Should include Platform when provided' {
            $script:result.Platform | Should -Be 'Windows'
        }

        It 'Should include State when provided' {
            $script:result.State | Should -Be 'enabled'
        }
    }

    Context 'Optional properties when NOT provided' {
        BeforeAll {
            $script:result = New-HydrationResult -Name 'Test' -Action 'Deleted' -Status 'Success'
        }

        It 'Should NOT have Path property' {
            $script:result.PSObject.Properties['Path'] | Should -BeNullOrEmpty
        }

        It 'Should NOT have Type property' {
            $script:result.PSObject.Properties['Type'] | Should -BeNullOrEmpty
        }

        It 'Should NOT have Id property' {
            $script:result.PSObject.Properties['Id'] | Should -BeNullOrEmpty
        }

        It 'Should NOT have Platform property' {
            $result.PSObject.Properties['Platform'] | Should -BeNullOrEmpty
        }

        It 'Should NOT have State property' {
            $result.PSObject.Properties['State'] | Should -BeNullOrEmpty
        }
    }

    Context 'Selective optional properties' {
        It 'Should add only Path when only Path is provided' {
            $result = New-HydrationResult -Name 'Test' -Action 'Created' -Status 'OK' -Path '/test.json'
            $result.PSObject.Properties['Path'] | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties['Type'] | Should -BeNullOrEmpty
            $result.PSObject.Properties['Id'] | Should -BeNullOrEmpty
        }

        It 'Should add only Platform when only Platform is provided' {
            $result = New-HydrationResult -Name 'Test' -Action 'Created' -Status 'OK' -Platform 'macOS'
            $result.PSObject.Properties['Platform'] | Should -Not -BeNullOrEmpty
            $result.Platform | Should -Be 'macOS'
            $result.PSObject.Properties['Path'] | Should -BeNullOrEmpty
        }
    }

    Context 'Optional property edge values' {
        It 'Should include string zero as an explicit optional value' {
            $result = New-HydrationResult -Name 'Test' -Action 'Created' -Status 'OK' -Id '0'

            $result.Id | Should -Be '0'
        }

        It 'Should not include whitespace-only optional values' {
            $result = New-HydrationResult -Name 'Test' -Action 'Created' -Status 'OK' -Path '   '

            $result.PSObject.Properties['Path'] | Should -BeNullOrEmpty
        }
    }

    Context 'Return type' {
        It 'Should return a PSCustomObject' {
            $result = New-HydrationResult -Name 'Test' -Action 'Created' -Status 'Success'
            $result | Should -BeOfType [PSCustomObject]
        }
    }

    Context 'Different action types' -ForEach @(
        @{ Action = 'Created' }
        @{ Action = 'Updated' }
        @{ Action = 'Deleted' }
        @{ Action = 'Skipped' }
        @{ Action = 'WouldCreate' }
        @{ Action = 'Failed' }
    ) {
        It 'Should accept Action "<Action>"' {
            $result = New-HydrationResult -Name 'Test' -Action $Action -Status 'OK'
            $result.Action | Should -Be $Action
        }
    }
}
