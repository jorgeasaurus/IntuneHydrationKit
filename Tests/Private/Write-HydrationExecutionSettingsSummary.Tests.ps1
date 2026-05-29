#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Hydration/Format-HydrationDisplayMessage.ps1
    . $PSScriptRoot/../../Private/Hydration/Get-HydrationTenantDisplay.ps1
    . $PSScriptRoot/../../Private/Configuration/Write-HydrationExecutionSettingsSummary.ps1

    function Remove-AnsiFormatting {
        param([string]$Text)

        $escapePattern = [regex]::Escape([string][char]27) + '\[[0-9;]*m'
        return ($Text -replace $escapePattern, '')
    }
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

        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '🎯 Target Tenant: 12345678-****-****-****-123456789abc' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '🏢 Tenant Name: contoso.onmicrosoft.com' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '🔐 Authentication Mode: interactive' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '⚙️ Options:' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -match 'create\s+True' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '📦 Imports Enabled:' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -match 'dynamicGroups\s+True' } -Times 1
        Should -Invoke Write-Information -ParameterFilter { (Remove-AnsiFormatting -Text $MessageData) -eq '🧭 Platform Filter: windows, ios' } -Times 1
        Should -Invoke Write-Information -Exactly 8
    }
}
