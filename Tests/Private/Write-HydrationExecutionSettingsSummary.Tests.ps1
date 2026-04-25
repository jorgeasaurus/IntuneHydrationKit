#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Write-HydrationExecutionSettingsSummary.ps1
}

Describe 'Write-HydrationExecutionSettingsSummary' {
    It 'Should emit the execution summary through the information stream' {
        Mock Get-ObfuscatedTenantId { '12345678-****-****-****-123456789abc' }
        Mock Write-Information { }

        $settings = @{
            tenant         = @{
                tenantId   = '12345678-1234-1234-1234-123456789abc'
                tenantName = 'contoso.onmicrosoft.com'
            }
            authentication = @{
                mode = 'interactive'
            }
            options        = @{
                create = $true
                delete = $false
            }
            imports        = @{
                dynamicGroups = $true
            }
            platforms      = @('windows', 'ios')
        }

        Write-HydrationExecutionSettingsSummary -Settings $settings

        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq 'Target Tenant: 12345678-****-****-****-123456789abc' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq 'Tenant Name: contoso.onmicrosoft.com' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq 'Authentication Mode: interactive' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq 'Options:' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -match 'create\s+True' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq 'Imports Enabled:' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -match 'dynamicGroups\s+True' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { $MessageData -eq 'Platform Filter: windows, ios' } -Times 1
        Should -Invoke Write-Information -Exactly 8
    }
}
