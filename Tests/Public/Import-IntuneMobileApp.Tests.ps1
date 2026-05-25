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
            $relativePath = if ($template -is [hashtable] -and $template.ContainsKey('RelativePath')) {
                [string]$template.RelativePath
            } elseif ($template.PSObject.Properties['RelativePath']) {
                [string]$template.RelativePath
            } else {
                $null
            }
            $fileName = if ($relativePath) {
                $relativePath
            } elseif ($template.displayName) {
                "$($template.displayName -replace '[^a-zA-Z0-9]', '-').json"
            } else {
                "template-$(Get-Random).json"
            }
            $filePath = Join-Path $tempDir $fileName
            $fileDirectory = Split-Path -Path $filePath -Parent
            if (-not (Test-Path -Path $fileDirectory)) {
                New-Item -Path $fileDirectory -ItemType Directory -Force | Out-Null
            }

            $templateBody = [ordered]@{}
            if ($template -is [hashtable]) {
                foreach ($key in $template.Keys) {
                    if ($key -ne 'RelativePath') {
                        $templateBody[$key] = $template[$key]
                    }
                }
            } else {
                foreach ($property in $template.PSObject.Properties) {
                    if ($property.Name -ne 'RelativePath') {
                        $templateBody[$property.Name] = $property.Value
                    }
                }
            }
            $templateBody | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
        }

        return $tempDir
    }

    function New-TestExistingMobileApp {
        param(
            [Parameter()]
            [string]$Id = 'existing-id',

            [Parameter()]
            [string]$DisplayName = 'Existing App - [IHD]',

            [Parameter()]
            [AllowNull()]
            [string]$Notes = 'Imported by Intune Hydration Kit'
        )

        @{
            id          = $Id
            displayName = $DisplayName
            notes       = $Notes
        }
    }

    function Set-TestExistingMobileAppsMock {
        param(
            [Parameter(Mandatory)]
            [object[]]$Apps
        )

        $script:testExistingMobileApps = @($Apps)
        Mock Invoke-MgGraphRequest {
            param($Method)
            if ($Method -eq 'GET') {
                return @{
                    value             = @($script:testExistingMobileApps)
                    '@odata.nextLink' = $null
                }
            }
        } -ModuleName IntuneHydrationKit
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

            $result = Import-IntuneMobileApp -TemplatePath $emptyDir
            $result | Should -BeNullOrEmpty
        }

        It 'Should warn when no mobile app templates match requested template IDs' {
            $tempDir = New-TestTemplateDirectory -Templates @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Existing App'
                    publisher     = 'Test Publisher'
                }
            )

            $warnings = @()
            $result = Import-IntuneMobileApp -TemplatePath $tempDir -TemplateId 'DoesNotExist' -WarningVariable warnings -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            $warnings[0].Message | Should -Be 'No mobile app templates matched TemplateId value(s): DoesNotExist'
        }

        It 'Should match legacy Windows mobile app TemplateIds in nested platform directories' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
            } -ModuleName IntuneHydrationKit

            $tempDir = New-TestTemplateDirectory -Templates @(
                @{ RelativePath = 'Windows/Store/AdobeAcrobatReaderDC.json'; '@odata.type' = '#microsoft.graph.winGetApp'; displayName = 'Adobe Acrobat Reader DC'; publisher = 'Test Publisher' }
                @{ RelativePath = 'Windows/Store/CompanyPortal.json'; '@odata.type' = '#microsoft.graph.winGetApp'; displayName = 'Company Portal'; publisher = 'Test Publisher' }
                @{ RelativePath = 'Windows/Store/PowerShell.json'; '@odata.type' = '#microsoft.graph.winGetApp'; displayName = 'PowerShell'; publisher = 'Test Publisher' }
                @{ RelativePath = 'Windows/Store/Spotify-MusicandPodcasts.json'; '@odata.type' = '#microsoft.graph.winGetApp'; displayName = 'Spotify Music and Podcasts'; publisher = 'Test Publisher' }
                @{ RelativePath = 'Windows/Store/WhatsApp.json'; '@odata.type' = '#microsoft.graph.winGetApp'; displayName = 'WhatsApp'; publisher = 'Test Publisher' }
                @{ RelativePath = 'Windows/M365/M365Apps.json'; '@odata.type' = '#microsoft.graph.officeSuiteApp'; displayName = 'M365 Apps'; publisher = 'Microsoft' }
            )

            $warnings = @()
            $result = Import-IntuneMobileApp `
                -TemplatePath $tempDir `
                -Platform Windows `
                -TemplateId @('AdobeAcrobatReaderDC', 'CompanyPortal', 'PowerShell', 'SpotifyMusicAndPodcasts', 'WhatsApp', 'M365Apps') `
                -WhatIf `
                -WarningVariable warnings `
                -WarningAction SilentlyContinue

            $warnings | Should -BeNullOrEmpty
            $result | Should -HaveCount 6
            @($result | Where-Object { $_.Action -ne 'WouldCreate' }) | Should -BeNullOrEmpty
        }
    }

    Context 'App Creation' {
        BeforeEach {
            # Mock Graph API calls
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-app-id'; displayName = 'Test App' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should create app from valid template' {
            $templates = @(
                [PSCustomObject]@{
                    '@odata.type'     = '#microsoft.graph.winGetApp'
                    displayName       = 'Test WinGet App'
                    publisher         = 'Test Publisher'
                    packageIdentifier = '9WZDNCRFJ3PZ'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Created'
            $result[0].Name | Should -Be 'Test WinGet App - [IHD]'
        }

        It 'Should ignore WinGet catalog JSON files in the generic mobile app importer' {
            $script:capturedBatchBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    $script:capturedBatchBody = $Body | ConvertFrom-Json
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'legacy-app-id' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $tempDir = New-TestTemplateDirectory -Templates @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Legacy Mobile App'
                    publisher     = 'Test Publisher'
                }
            )

            $winGetAppPath = Join-Path $tempDir 'Windows/WinGet/Apps'
            $winGetPresetPath = Join-Path $tempDir 'Windows/WinGet/Presets'
            $winGetSchemaPath = Join-Path $tempDir 'Windows/WinGet/Schemas'
            New-Item -Path $winGetAppPath, $winGetPresetPath, $winGetSchemaPath -ItemType Directory -Force | Out-Null

            @{
                '$schema'         = '../Schemas/winGetAppTemplate.schema.json'
                schemaVersion     = '1.0.0'
                templateId        = 'catalog-app'
                displayName       = 'Catalog App'
                packageIdentifier = 'Vendor.CatalogApp'
                package           = @{ match = @{ packageIdentifier = 'Vendor.CatalogApp' } }
                install           = @{ command = 'winget install --id Vendor.CatalogApp --silent' }
                icon              = @{ sourceType = 'file'; fileName = 'catalog.png' }
                resolvedPackage   = @{ selectedInstaller = @{}; manifestSource = @{ repository = 'microsoft/winget-pkgs' } }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $winGetAppPath 'catalog-app.json') -Encoding UTF8
            @{
                '$schema'     = '../Schemas/winGetAppPreset.schema.json'
                schemaVersion = '1.0.0'
                presetId      = 'catalog-preset'
                displayName   = 'Catalog Preset'
                appIds        = @('catalog-app')
            } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $winGetPresetPath 'catalog-preset.json') -Encoding UTF8
            @{ '$schema' = 'https://json-schema.org/draft/2020-12/schema'; type = 'object' } |
                ConvertTo-Json -Depth 10 |
                Set-Content -Path (Join-Path $winGetSchemaPath 'catalog.schema.json') -Encoding UTF8

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Created'
            $result[0].Name | Should -Be 'Legacy Mobile App - [IHD]'
            $script:capturedBatchBody.requests | Should -HaveCount 1
            $script:capturedBatchBody.requests[0].body.displayName | Should -Be 'Legacy Mobile App - [IHD]'
        }

        It 'Should filter legacy mobile app templates by template ID' {
            $script:capturedBatchBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    $script:capturedBatchBody = $Body | ConvertFrom-Json
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'spotify-app-id' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $tempDir = New-TestTemplateDirectory -Templates @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Spotify Music and Podcasts'
                    publisher     = 'Spotify'
                },
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Other App'
                    publisher     = 'Other'
                }
            )

            $result = Import-IntuneMobileApp -TemplatePath $tempDir -TemplateId 'SpotifyMusicAndPodcasts'

            $result | Should -HaveCount 1
            $result[0].Name | Should -Be 'Spotify Music and Podcasts - [IHD]'
            $script:capturedBatchBody.requests | Should -HaveCount 1
            $script:capturedBatchBody.requests[0].body.displayName | Should -Be 'Spotify Music and Podcasts - [IHD]'
        }

        It 'Should skip apps that already exist with hydration kit tag' {
            Set-TestExistingMobileAppsMock -Apps @(New-TestExistingMobileApp)

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Existing App'
                    publisher     = 'Test Publisher'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Skipped'
            $result[0].Status | Should -Be 'Already exists'
        }

        It 'Should skip legacy prefixed apps that already exist with hydration kit tag' {
            Set-TestExistingMobileAppsMock -Apps @(
                New-TestExistingMobileApp -Id 'legacy-prefixed-id' -DisplayName '[IHD] Existing App'
            )

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Existing App'
                    publisher     = 'Test Publisher'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Skipped'
            $result[0].Name | Should -Be 'Existing App - [IHD]'
            $result[0].Id | Should -Be 'legacy-prefixed-id'
        }

        It 'Should create app when existing app lacks hydration kit tag' {
            $script:capturedBatchBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{
                        value             = @(
                            @{ id = 'untagged-id'; displayName = 'PowerShell'; notes = '' }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    $script:capturedBatchBody = $Body | ConvertFrom-Json
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-kit-id' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'PowerShell'
                    publisher     = 'Microsoft'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Created'
            $result[0].Name | Should -Be 'PowerShell - [IHD]'
            $script:capturedBatchBody.requests[0].body.notes | Should -BeLike '*Imported by Intune Hydration Kit*'
        }

        It 'Should create app when existing app has null notes' {
            $script:capturedBatchBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{
                        value             = @(
                            @{ id = 'null-notes-id'; displayName = 'Slack'; notes = $null }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    $script:capturedBatchBody = $Body | ConvertFrom-Json
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-kit-id' } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Slack'
                    publisher     = 'Slack Technologies'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Created'
            $result[0].Name | Should -Be 'Slack - [IHD]'
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

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -Be 'Missing displayName'
        }

        It 'Should add hydration kit marker to notes field' {
            $script:capturedBatchBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    $script:capturedBatchBody = $Body | ConvertFrom-Json
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-id' } }
                        )
                    }
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

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result[0].Action | Should -Be 'Created'
            $script:capturedBatchBody.requests[0].body.notes | Should -BeLike '*Imported by Intune Hydration Kit*'
        }

        It 'Should preserve existing notes and append marker' {
            $script:capturedBatchBody = $null
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    $script:capturedBatchBody = $Body | ConvertFrom-Json
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-id' } }
                        )
                    }
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

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result[0].Action | Should -Be 'Created'
            $script:capturedBatchBody.requests[0].body.notes | Should -BeLike 'Existing notes here*'
            $script:capturedBatchBody.requests[0].body.notes | Should -BeLike '*Imported by Intune Hydration Kit*'
        }
    }

    Context 'App Deletion' {
        BeforeEach {
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should delete apps with hydration kit marker in notes' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{
                        value             = @(
                            @{
                                id          = 'app-to-delete'
                                displayName = 'Hydration Kit App'
                                notes       = 'Imported by Intune Hydration Kit'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 204 }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            # Create a template file so the function doesn't exit early
            $templates = @(
                [PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Hydration Kit App'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting
            $result = @($result | Where-Object { $_ -ne $null })

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Deleted'
            $result[0].Name | Should -Be 'Hydration Kit App'
        }

        It 'Should skip apps without hydration kit marker' {
            Set-TestExistingMobileAppsMock -Apps @(
                New-TestExistingMobileApp -Id 'manual-app' -DisplayName 'Manually Created App' -Notes 'Created manually by admin'
            )

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'App To Delete'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting

            $result | Should -BeNullOrEmpty
        }

        It 'Should skip apps with null notes' {
            Set-TestExistingMobileAppsMock -Apps @(
                New-TestExistingMobileApp -Id 'app-no-notes' -DisplayName 'App Without Notes' -Notes $null
            )

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Delete Error App'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting

            $result | Should -BeNullOrEmpty
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

            $result = Import-IntuneMobileApp -TemplatePath $tempDir -WhatIf

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'WouldCreate'
            $result[0].Status | Should -Be 'DryRun'
        }

        It 'Should return WouldDelete action in WhatIf mode for deletion' {
            Set-TestExistingMobileAppsMock -Apps @(
                New-TestExistingMobileApp -Id 'app-id' -DisplayName 'App To Delete'
            )

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'App To Delete'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting -WhatIf

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'WouldDelete'
            $result[0].Status | Should -Be 'DryRun'
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
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 400; body = @{ error = @{ message = 'Graph API error' } } }
                        )
                    }
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

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
        }

        It 'Should handle Graph API errors during deletion' {
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    return @{
                        value             = @(
                            @{
                                id          = 'app-id'
                                displayName = 'Delete Error App'
                                notes       = 'Imported by Intune Hydration Kit'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 400; body = @{ error = @{ message = 'Delete failed' } } }
                        )
                    }
                }
            } -ModuleName IntuneHydrationKit

            # Create a template file so the function doesn't exit early
            $templates = @(
                @{
                    '@odata.type' = '#microsoft.graph.winGetApp'
                    displayName   = 'Delete Error App'
                    publisher     = 'Test'
                }
            )
            $tempDir = New-TestTemplateDirectory -Templates $templates

            $result = Import-IntuneMobileApp -TemplatePath $tempDir -RemoveExisting

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Delete failed*'
        }
    }

    Context 'Pagination Support' {
        BeforeEach {
            Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        }

        It 'Should handle paginated results from Graph API' {
            $script:pageCount = 0
            Mock Invoke-MgGraphRequest {
                param($Method)
                if ($Method -eq 'GET') {
                    $script:pageCount++
                    if ($script:pageCount -eq 1) {
                        return @{
                            value             = @(
                                @{ id = 'app1'; displayName = 'App 1 - [IHD]'; notes = 'Imported by Intune Hydration Kit' }
                            )
                            '@odata.nextLink' = 'https://graph.microsoft.com/beta/next-page'
                        }
                    } else {
                        return @{
                            value             = @(
                                @{ id = 'app2'; displayName = 'App 2 - [IHD]'; notes = 'Imported by Intune Hydration Kit' }
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

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Where-Object { $_.Action -eq 'Skipped' } | Should -HaveCount 2
        }
    }

    Context 'Result Object Structure' {
        BeforeEach {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                if ($Method -eq 'POST' -and $Uri -like '*$batch*') {
                    return @{
                        responses = @(
                            @{ id = '1'; status = 201; body = @{ id = 'new-id' } }
                        )
                    }
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

            $result = Import-IntuneMobileApp -TemplatePath $tempDir

            $result | Should -HaveCount 1
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Action'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'Type'
            $result[0].Type | Should -Be 'MobileApp'
        }
    }
}
