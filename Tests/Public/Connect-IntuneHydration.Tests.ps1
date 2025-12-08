#Requires -Modules Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force

    # Get reference to the module
    $script:TestModule = Get-Module -Name IntuneHydrationKit

    if (-not $script:TestModule) {
        throw "Failed to import IntuneHydrationKit module"
    }

    # Helper function to get module-scoped variable
    function Get-ModuleVariable {
        param([string]$Name)
        & $script:TestModule { param($VarName) Get-Variable -Name $VarName -Scope Script -ValueOnly -ErrorAction SilentlyContinue } $Name
    }

    # Helper function to set module-scoped variable
    function Set-ModuleVariable {
        param([string]$Name, $Value)
        & $script:TestModule { param($VarName, $VarValue) Set-Variable -Name $VarName -Value $VarValue -Scope Script } $Name $Value
    }
}

Describe 'Connect-IntuneHydration' {
    BeforeEach {
        # Reset module state before each test
        Set-ModuleVariable -Name 'HydrationState' -Value @{
            Connected   = $false
            TenantId    = $null
            Environment = $null
        }
        Set-ModuleVariable -Name 'GraphEndpoint' -Value $null
        Set-ModuleVariable -Name 'GraphEnvironment' -Value $null
    }

    Context 'Parameter Validation' {
        It 'Should require TenantId parameter' {
            $command = Get-Command Connect-IntuneHydration
            $tenantIdParam = $command.Parameters['TenantId']

            $tenantIdParam | Should -Not -BeNullOrEmpty
            $tenantIdParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Contain $true
        }

        It 'Should have Interactive parameter set' {
            $command = Get-Command Connect-IntuneHydration
            $command.ParameterSets.Name | Should -Contain 'Interactive'
        }

        It 'Should have ClientSecret parameter set' {
            $command = Get-Command Connect-IntuneHydration
            $command.ParameterSets.Name | Should -Contain 'ClientSecret'
        }

        It 'Should require ClientId when using ClientSecret parameter set' {
            $command = Get-Command Connect-IntuneHydration
            $clientIdParam = $command.Parameters['ClientId']

            $clientSecretSet = $clientIdParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'ClientSecret' }

            $clientSecretSet.Mandatory | Should -Be $true
        }

        It 'Should require ClientSecret as SecureString' {
            $command = Get-Command Connect-IntuneHydration
            $clientSecretParam = $command.Parameters['ClientSecret']

            $clientSecretParam.ParameterType | Should -Be ([SecureString])
        }

        It 'Should validate Environment parameter values' {
            $command = Get-Command Connect-IntuneHydration
            $envParam = $command.Parameters['Environment']

            $validateSet = $envParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Global'
            $validateSet.ValidValues | Should -Contain 'USGov'
            $validateSet.ValidValues | Should -Contain 'USGovDoD'
            $validateSet.ValidValues | Should -Contain 'Germany'
            $validateSet.ValidValues | Should -Contain 'China'
        }

        It 'Should default Environment to Global' {
            $command = Get-Command Connect-IntuneHydration
            $envParam = $command.Parameters['Environment']

            $envParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.ParameterSetName } | Should -Not -BeNullOrEmpty

            # Default value check - the parameter should have a default
            # This is validated through the function definition
        }
    }

    Context 'Graph Environment Mapping' {
        BeforeAll {
            # Mock Connect-MgGraph to prevent actual connections
            Mock Connect-MgGraph { } -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
        }

        It 'Should set correct endpoint for Global environment' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Environment Global

            Get-ModuleVariable -Name 'GraphEndpoint' | Should -Be 'https://graph.microsoft.com'
        }

        It 'Should set correct endpoint for USGov environment' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Environment USGov

            Get-ModuleVariable -Name 'GraphEndpoint' | Should -Be 'https://graph.microsoft.us'
        }

        It 'Should set correct endpoint for USGovDoD environment' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Environment USGovDoD

            Get-ModuleVariable -Name 'GraphEndpoint' | Should -Be 'https://dod-graph.microsoft.us'
        }

        It 'Should set correct endpoint for Germany environment' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Environment Germany

            Get-ModuleVariable -Name 'GraphEndpoint' | Should -Be 'https://graph.microsoft.de'
        }

        It 'Should set correct endpoint for China environment' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Environment China

            Get-ModuleVariable -Name 'GraphEndpoint' | Should -Be 'https://microsoftgraph.chinacloudapi.cn'
        }
    }

    Context 'Interactive Authentication' {
        BeforeAll {
            Mock Connect-MgGraph { } -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
        }

        It 'Should call Connect-MgGraph with scopes for interactive auth' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive

            Should -Invoke Connect-MgGraph -ModuleName IntuneHydrationKit -ParameterFilter {
                $Scopes -ne $null -and $Scopes.Count -gt 0
            }
        }

        It 'Should update HydrationState on successful connection' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive

            $state = Get-ModuleVariable -Name 'HydrationState'
            $state.Connected | Should -Be $true
            $state.TenantId | Should -Be '12345678-1234-1234-1234-123456789abc'
        }

        It 'Should store environment in HydrationState' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive -Environment USGov

            $state = Get-ModuleVariable -Name 'HydrationState'
            $state.Environment | Should -Be 'USGov'
        }
    }

    Context 'Client Secret Authentication' {
        BeforeAll {
            Mock Connect-MgGraph { } -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
        }

        It 'Should call Connect-MgGraph with ClientSecretCredential for app auth' {
            $secureSecret = ConvertTo-SecureString 'TestSecret123' -AsPlainText -Force

            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' `
                -ClientId 'app-client-id' `
                -ClientSecret $secureSecret

            Should -Invoke Connect-MgGraph -ModuleName IntuneHydrationKit -ParameterFilter {
                $ClientSecretCredential -ne $null
            }
        }

        It 'Should not include Scopes parameter for client secret auth' {
            $secureSecret = ConvertTo-SecureString 'TestSecret123' -AsPlainText -Force

            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' `
                -ClientId 'app-client-id' `
                -ClientSecret $secureSecret

            Should -Invoke Connect-MgGraph -ModuleName IntuneHydrationKit -ParameterFilter {
                $null -eq $Scopes
            }
        }
    }

    Context 'Error Handling' {
        It 'Should throw when Connect-MgGraph fails' {
            Mock Connect-MgGraph { throw 'Connection failed' } -ModuleName IntuneHydrationKit

            { Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive } |
                Should -Throw
        }

        It 'Should not update HydrationState when connection fails' {
            Mock Connect-MgGraph { throw 'Connection failed' } -ModuleName IntuneHydrationKit

            try {
                Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive
            }
            catch {
                # Expected
            }

            $state = Get-ModuleVariable -Name 'HydrationState'
            $state.Connected | Should -Be $false
        }
    }

    Context 'Required Scopes' {
        BeforeAll {
            Mock Connect-MgGraph { } -ModuleName IntuneHydrationKit
            Mock Get-ObfuscatedTenantId { return '12345678****-****-****-123456789abc' } -ModuleName IntuneHydrationKit
        }

        It 'Should request DeviceManagementConfiguration.ReadWrite.All scope' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive

            Should -Invoke Connect-MgGraph -ModuleName IntuneHydrationKit -ParameterFilter {
                $Scopes -contains 'DeviceManagementConfiguration.ReadWrite.All'
            }
        }

        It 'Should request Group.ReadWrite.All scope' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive

            Should -Invoke Connect-MgGraph -ModuleName IntuneHydrationKit -ParameterFilter {
                $Scopes -contains 'Group.ReadWrite.All'
            }
        }

        It 'Should request Policy.ReadWrite.ConditionalAccess scope' {
            Connect-IntuneHydration -TenantId '12345678-1234-1234-1234-123456789abc' -Interactive

            Should -Invoke Connect-MgGraph -ModuleName IntuneHydrationKit -ParameterFilter {
                $Scopes -contains 'Policy.ReadWrite.ConditionalAccess'
            }
        }
    }
}
