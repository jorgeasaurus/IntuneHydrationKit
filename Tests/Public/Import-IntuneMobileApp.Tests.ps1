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

    # Helper to create temp template directory with test files
    function New-TestTemplateDirectory {
        param(
            [array]$Templates
        )
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "MobileAppsTest-$(Get-Random)"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        foreach ($template in $Templates) {
            $fileName = if ($template.displayName) {
                "$($template.displayName -replace '[^a-zA-Z0-9]', '-').json"
            } else {
                "template-$(Get-Random).json"
            }
            $filePath = Join-Path $tempDir $fileName
            $template | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
        }

        return $tempDir
    }
}

AfterAll {
    # Cleanup any temp directories
    Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Directory -Filter "MobileAppsTest-*" |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Import-IntuneMobileApp' {
    Context 'Parameter Validation' {
        It 'Should have TemplatePath parameter' {
            $command = Get-Command Import-IntuneMobileApp
            $param = $command.Parameters['TemplatePath']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([string])
        }

        It 'Should have RemoveExisting switch parameter' {
            $command = Get-Command Import-IntuneMobileApp
            $param = $command.Parameters['RemoveExisting']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should support ShouldProcess (WhatIf)' {
            $command = Get-Command Import-IntuneMobileApp
            $command.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }

        It 'Should not require any mandatory parameters' {
            $command = Get-Command Import-IntuneMobileApp
            $mandatoryParams = $command.Parameters.Values | Where-Object {
                $_.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }
            }

            $mandatoryParams | Should -BeNullOrEmpty
        }
    }

    Context 'Template Directory Handling' {
        It 'Should return empty array when template directory does not exist' {
            $result = Import-IntuneMobileApp -TemplatePath '/nonexistent/path'

            $result | Should -BeNullOrEmpty
        }

        It 'Should return empty array when no template files found' {
            $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) "EmptyMobileAppsTest-$(Get-Random)"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            try {
                $result = Import-IntuneMobileApp -TemplatePath $emptyDir
                $result | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'App Creation' {
        BeforeEach {
            # Mock Graph API calls
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-app-id'; displayName = 'Test App' }
                }
            } -ModuleName IntuneHydrationKit

            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should create app from valid template' {
            $templates = @(
                [PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Test WinGet App'
                    publisher     = 'Test Publisher'
                    packageIdentifier = '9WZDNCRFJ3PZ'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'Created'
                $result[0].Name | Should -Be 'Test WinGet App'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should skip apps that already exist' {
            # Mock existing app
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{ id = 'existing-id'; displayName = 'Existing App'; notes = '' }
                        )
                        '@odata.nextLink' = $null
                    }
                }
            } -ModuleName IntuneHydrationKit

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Existing App'
                    publisher     = 'Test Publisher'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'Skipped'
                $result[0].Status | Should -Be 'Already exists'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should fail templates missing displayName' {
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    publisher     = 'Test Publisher'
                    # Missing displayName
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'Failed'
                $result[0].Status | Should -Be 'Missing displayName'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should add hydration kit marker to notes field' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST') {
                    $script:capturedBody = $Body | ConvertFrom-Json
                    return @{ id = 'new-id' }
                }
            } -ModuleName IntuneHydrationKit

            $templates = @(
                [PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Test App With Notes'
                    publisher     = 'Test Publisher'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                $result[0].Action | Should -Be 'Created'
                $script:capturedBody.notes | Should -BeLike '*Imported by Intune-Hydration-Kit*'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should preserve existing notes and append marker' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST') {
                    $script:capturedBody = $Body | ConvertFrom-Json
                    return @{ id = 'new-id' }
                }
            } -ModuleName IntuneHydrationKit

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Test App With Existing Notes'
                    publisher     = 'Test Publisher'
                    notes         = 'Existing notes here'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                $result[0].Action | Should -Be 'Created'
                $script:capturedBody.notes | Should -BeLike 'Existing notes here*'
                $script:capturedBody.notes | Should -BeLike '*Imported by Intune-Hydration-Kit*'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'App Deletion' {
        BeforeEach {
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should delete apps with hydration kit marker in notes' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id = 'app-to-delete'
                                displayName = 'Hydration Kit App'
                                notes = 'Imported by Intune-Hydration-Kit'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Method -eq 'DELETE') {
                    return $null
                }
            } -ModuleName IntuneHydrationKit

            # Create a template file so the function doesn't exit early
            $templates = @(
                [PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Dummy Template'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting
                # Filter out null entries
                $result = @($result | Where-Object { $_ -ne $null })

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'Deleted'
                $result[0].Name | Should -Be 'Hydration Kit App'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should skip apps without hydration kit marker' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id = 'manual-app'
                                displayName = 'Manually Created App'
                                notes = 'Created manually by admin'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
            } -ModuleName IntuneHydrationKit

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Dummy Template'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting

                $result | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should skip apps with null notes' {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id = 'app-no-notes'
                                displayName = 'App Without Notes'
                                notes = $null
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
            } -ModuleName IntuneHydrationKit

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Dummy Template'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting

                $result | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
            } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return WouldCreate action in WhatIf mode' {
            $templates = @(
                [PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'WhatIf Test App'
                    publisher     = 'Test Publisher'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir -WhatIf

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'WouldCreate'
                $result[0].Status | Should -Be 'DryRun'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should return WouldDelete action in WhatIf mode for deletion' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id = 'app-id'
                                displayName = 'App To Delete'
                                notes = 'Imported by Intune-Hydration-Kit'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
            } -ModuleName IntuneHydrationKit

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Dummy Template'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting -WhatIf

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'WouldDelete'
                $result[0].Status | Should -Be 'DryRun'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Error Handling' {
        BeforeEach {
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
            Mock Get-GraphErrorMessage { return 'Graph API error' } -ModuleName IntuneHydrationKit
        }

        It 'Should handle Graph API errors during creation' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST') {
                    throw 'Graph API error'
                }
            } -ModuleName IntuneHydrationKit

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Error Test App'
                    publisher     = 'Test Publisher'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'Failed'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should handle Graph API errors during deletion' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{
                        value = @(
                            @{
                                id = 'app-id'
                                displayName = 'Delete Error App'
                                notes = 'Imported by Intune-Hydration-Kit'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Method -eq 'DELETE') {
                    throw 'Delete failed'
                }
            } -ModuleName IntuneHydrationKit

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Dummy Template'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting

                $result | Should -HaveCount 1
                $result[0].Action | Should -Be 'Failed'
                $result[0].Status | Should -BeLike 'Delete failed*'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Pagination Support' {
        BeforeEach {
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should handle paginated results from Graph API' {
            $script:pageCount = 0
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    $script:pageCount++
                    if ($script:pageCount -eq 1) {
                        return @{
                            value = @(
                                @{ id = 'app1'; displayName = 'App 1'; notes = '' }
                            )
                            '@odata.nextLink' = 'https://graph.microsoft.com/beta/next-page'
                        }
                    }
                    else {
                        return @{
                            value = @(
                                @{ id = 'app2'; displayName = 'App 2'; notes = '' }
                            )
                            '@odata.nextLink' = $null
                        }
                    }
                }
            } -ModuleName IntuneHydrationKit

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'App 1'
                    publisher     = 'Test'
                },
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'App 2'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                # Both apps should be skipped since they exist
                $result | Where-Object { $_.Action -eq 'Skipped' } | Should -HaveCount 2
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Result Object Structure' {
        BeforeEach {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST') {
                    return @{ id = 'new-id' }
                }
            } -ModuleName IntuneHydrationKit
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should return results with correct properties' {
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Result Test App'
                    publisher     = 'Test Publisher'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            try {
                $result = Import-IntuneMobileApp -TemplatePath $tempDir

                $result | Should -HaveCount 1
                $result[0].PSObject.Properties.Name | Should -Contain 'Name'
                $result[0].PSObject.Properties.Name | Should -Contain 'Action'
                $result[0].PSObject.Properties.Name | Should -Contain 'Status'
                $result[0].PSObject.Properties.Name | Should -Contain 'Type'
                $result[0].Type | Should -Be 'MobileApp'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
