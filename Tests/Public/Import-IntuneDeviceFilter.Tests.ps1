#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
}

Describe 'Import-IntuneDeviceFilter' {
    BeforeAll {
        Mock Write-HydrationLog -ModuleName IntuneHydrationKit
        Mock Get-GraphErrorMessage { return "Test error message" } -ModuleName IntuneHydrationKit
        Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit
        Mock Start-Sleep -ModuleName IntuneHydrationKit
    }

    Context 'Parameter Validation' {
        It 'Should have TemplatePath parameter' {
            $command = Get-Command Import-IntuneDeviceFilter
            $param = $command.Parameters['TemplatePath']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have Platform parameter with ValidateSet' {
            $command = Get-Command Import-IntuneDeviceFilter
            $param = $command.Parameters['Platform']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Windows'
            $validateSet.ValidValues | Should -Contain 'macOS'
            $validateSet.ValidValues | Should -Contain 'iOS'
            $validateSet.ValidValues | Should -Contain 'Android'
            $validateSet.ValidValues | Should -Contain 'All'
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command Import-IntuneDeviceFilter
            $cmdletBinding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBinding.SupportsShouldProcess | Should -Be $true
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneDeviceFilter
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Create Mode - Device Filters' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Windows-Filters.json'
                        Name     = 'Windows-Filters.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "filters": [
        {
            "displayName": "Windows 11 Devices",
            "description": "Filter for Windows 11 devices",
            "platform": "windows10AndLater",
            "rule": "(device.osVersion -startsWith \"10.0.22000\")"
        }
    ]
}
'@
            } -ModuleName IntuneHydrationKit
        }

        It 'Should prefetch existing filters' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                return @{ id = 'new-filter-id'; displayName = 'Windows 11 Devices' }
            } -ModuleName IntuneHydrationKit

            Import-IntuneDeviceFilter -Platform Windows

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*assignmentFilters*'
            }
        }

        It 'Should skip filter if it already exists' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @(@{ id = 'existing-id'; displayName = 'Windows 11 Devices'; description = 'Existing filter' }) }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Skipped'
        }

        It 'Should create filter if it does not exist' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-filter-id'; displayName = 'Windows 11 Devices' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'Created'
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*assignmentFilters*'
            }
        }

        It 'Should append hydration marker to description' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    $Body.description | Should -BeLike '*Imported by Intune Hydration Kit*'
                    return @{ id = 'new-filter-id'; displayName = 'Windows 11 Devices' }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneDeviceFilter -Platform Windows
        }
    }

    Context 'Create Mode - Multiple Filters in Template' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{
                        FullName = 'TestPath\Windows-Filters.json'
                        Name     = 'Windows-Filters.json'
                    })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                @'
{
    "filters": [
        {
            "displayName": "Windows 11 Devices",
            "platform": "windows10AndLater",
            "rule": "(device.osVersion -startsWith \"10.0.22000\")"
        },
        {
            "displayName": "Corporate Devices",
            "platform": "windows10AndLater",
            "rule": "(device.deviceOwnership -eq \"Corporate\")"
        }
    ]
}
'@
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-filter-id'; displayName = 'Created Filter' }
                }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should create all filters from template' {
            $result = Import-IntuneDeviceFilter -Platform Windows

            $result.Count | Should -Be 2
            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST'
            } -Times 2
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Filters.json'; Name = 'Windows-Filters.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"filters": [{"displayName": "Test Filter", "platform": "windows10AndLater", "rule": "(device.osVersion -eq \"10.0\")"}]}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should not call POST when WhatIf is specified' {
            Import-IntuneDeviceFilter -Platform Windows -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'POST'
            } -Times 0
        }

        It 'Should return WouldCreate action when WhatIf is specified' {
            $result = Import-IntuneDeviceFilter -Platform Windows -WhatIf

            $result[0].Action | Should -Be 'WouldCreate'
        }
    }

    Context 'Delete Mode' {
        BeforeAll {
            # Mock template path as existing but empty - RemoveExisting still needs to fetch existing filters
            Mock Test-Path { return $true } -ModuleName IntuneHydrationKit
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Filters.json'; Name = 'Windows-Filters.json' })
            } -ModuleName IntuneHydrationKit
            Mock Get-Content {
                '{"filters": []}'
            } -ModuleName IntuneHydrationKit
        }

        It 'Should list existing filters when RemoveExisting is specified' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'filter-1'; displayName = 'Filter 1'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            Import-IntuneDeviceFilter -RemoveExisting -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ModuleName IntuneHydrationKit -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like '*assignmentFilters*'
            }
        }

        It 'Should only delete filters with hydration marker' {
            Mock Test-HydrationKitObject {
                param($Description)
                return $Description -like '*Imported by Intune Hydration Kit*'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'filter-1'; displayName = 'Hydration Filter'; description = 'Imported by Intune Hydration Kit' },
                            @{ id = 'filter-2'; displayName = 'Manual Filter'; description = 'Created manually' }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -RemoveExisting -WhatIf

            $deletedFilters = $result | Where-Object { $_.Action -eq 'WouldDelete' }
            $deletedFilters.Count | Should -Be 1
            $deletedFilters[0].Name | Should -Be 'Hydration Filter'
        }

        It 'Should delete filters when RemoveExisting is specified' {
            Mock Test-HydrationKitObject { return $true } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'filter-1'; displayName = 'Test Filter'; description = 'Imported by Intune Hydration Kit' }
                        )
                    }
                }
                if ($Method -eq 'DELETE') {
                    return $null
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -RemoveExisting -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            # Filter out null entries that may appear in the results
            $deletedItems = @($result | Where-Object { $_.Action -eq 'Deleted' })
            $deletedItems.Count | Should -Be 1
            $deletedItems[0].Name | Should -Be 'Test Filter'
        }
    }

    Context 'Error Handling' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Filters.json'; Name = 'Windows-Filters.json' })
            } -ModuleName IntuneHydrationKit
        }

        It 'Should handle API errors gracefully' {
            Mock Get-Content {
                '{"filters": [{"displayName": "Test Filter", "platform": "windows10AndLater", "rule": "(device.osVersion -eq \"10.0\")"}]}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
                if ($Method -eq 'POST') { throw "API Error" }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            $result[0].Action | Should -Be 'Failed'
        }

        It 'Should return empty array when no templates found' {
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            $result | Should -BeNullOrEmpty
        }

        It 'Should handle missing filters array in template' {
            Mock Get-Content {
                '{"displayName": "Invalid Template"}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike "*Missing 'filters' array*"
        }

        It 'Should skip filters missing displayName' {
            Mock Get-Content {
                '{"filters": [{"platform": "windows10AndLater", "rule": "(device.osVersion -eq \"10.0\")"}]}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            # No result should be returned for invalid filter
            $result | Should -BeNullOrEmpty
        }

        It 'Should skip filters missing platform' {
            Mock Get-Content {
                '{"filters": [{"displayName": "Test Filter", "rule": "(device.osVersion -eq \"10.0\")"}]}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            $result | Should -BeNullOrEmpty
        }

        It 'Should skip filters missing rule' {
            Mock Get-Content {
                '{"filters": [{"displayName": "Test Filter", "platform": "windows10AndLater"}]}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Retry Logic' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Filters.json'; Name = 'Windows-Filters.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"filters": [{"displayName": "Test Filter", "platform": "windows10AndLater", "rule": "(device.osVersion -eq \"10.0\")"}]}'
            } -ModuleName IntuneHydrationKit
        }

        It 'Should retry on server errors (500+)' {
            $callCount = 0
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
                if ($Method -eq 'POST') {
                    $script:callCount++
                    if ($script:callCount -lt 2) {
                        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError)
                        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Server Error", $response)
                        throw $exception
                    }
                    return @{ id = 'new-filter-id'; displayName = 'Test Filter' }
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneDeviceFilter -Platform Windows

            # Due to retry logic, should eventually succeed
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Platform Filtering' {
        It 'Should pass platform parameter to Get-FilteredTemplates' {
            Mock Get-FilteredTemplates { @() } -ModuleName IntuneHydrationKit

            Import-IntuneDeviceFilter -Platform Windows

            Should -Invoke Get-FilteredTemplates -ModuleName IntuneHydrationKit -ParameterFilter {
                $Platform -contains 'Windows'
            }
        }
    }

    Context 'Result Structure' {
        BeforeEach {
            Mock Get-FilteredTemplates {
                @([PSCustomObject]@{ FullName = 'TestPath\Windows-Filters.json'; Name = 'Windows-Filters.json' })
            } -ModuleName IntuneHydrationKit

            Mock Get-Content {
                '{"filters": [{"displayName": "Test Filter", "platform": "windows10AndLater", "rule": "(device.osVersion -eq \"10.0\")"}]}'
            } -ModuleName IntuneHydrationKit

            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') { return @{ value = @() } }
                return @{ id = 'filter-123'; displayName = 'Test Filter' }
            } -ModuleName IntuneHydrationKit
        }

        It 'Should return results with correct structure' {
            $result = Import-IntuneDeviceFilter -Platform Windows

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be 'Test Filter'
            $result[0].Type | Should -Be 'DeviceFilter'
            $result[0].Id | Should -Be 'filter-123'
            $result[0].Action | Should -Be 'Created'
        }
    }
}
