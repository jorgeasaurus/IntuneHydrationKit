#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\WinGet\Get-HydrationWinGetAppTemplates.ps1'
    . $functionPath
}

Describe 'Get-HydrationWinGetAppTemplates' {
    BeforeEach {
        $script:WinGetTemplatePath = Join-Path ([System.IO.Path]::GetTempPath()) "WinGetTemplates-$([guid]::NewGuid().ToString('N'))"
        $appsPath = Join-Path $script:WinGetTemplatePath 'Apps'
        $presetsPath = Join-Path $script:WinGetTemplatePath 'Presets'
        $schemasPath = Join-Path $script:WinGetTemplatePath 'Schemas'
        $null = New-Item -Path $appsPath, $presetsPath, $schemasPath -ItemType Directory -Force

        @{
            '$schema'              = 'https://json-schema.org/draft/2020-12/schema'
            type                   = 'object'
            required               = @('templateId', 'displayName', 'packageIdentifier')
            additionalProperties   = $true
            properties             = @{
                templateId        = @{ type = 'string' }
                displayName       = @{ type = 'string' }
                packageIdentifier = @{ type = 'string' }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $schemasPath 'winGetAppTemplate.schema.json') -Encoding utf8

        @{
            '$schema'              = 'https://json-schema.org/draft/2020-12/schema'
            type                   = 'object'
            required               = @('appIds')
            additionalProperties   = $true
            properties             = @{
                appIds = @{
                    type  = 'array'
                    items = @{ type = 'string' }
                }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $schemasPath 'winGetAppPreset.schema.json') -Encoding utf8

        foreach ($templateId in @('7-zip', 'notepad-plus-plus', 'vlc-media-player', 'google-chrome', 'putty', 'microsoft-edge', 'visual-studio-code', 'windows-terminal')) {
            @{
                templateId        = $templateId
                displayName       = $templateId
                packageIdentifier = "Contoso.$templateId"
            } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $appsPath "$templateId.json") -Encoding utf8
        }

        @{
            appIds = @('7-zip', 'notepad-plus-plus', 'vlc-media-player', 'google-chrome', 'putty', 'microsoft-edge')
        } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $presetsPath 'starter-pack.json') -Encoding utf8

        @{
            appIds = @('microsoft-edge', 'visual-studio-code', 'windows-terminal', 'google-chrome', 'putty', '7-zip')
        } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $presetsPath 'mobile-apps.json') -Encoding utf8
    }

    AfterEach {
        Remove-Item -Path $script:WinGetTemplatePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should load the starter pack preset templates' {
        $result = Get-HydrationWinGetAppTemplates -TemplatePath $script:WinGetTemplatePath -PresetId 'starter-pack'

        $result.Count | Should -BeGreaterThan 5
        $result.templateId | Should -Contain '7-zip'
        $result.templateId | Should -Contain 'notepad-plus-plus'
        $result.templateId | Should -Contain 'vlc-media-player'
        $result | Where-Object { $_.PresetId -eq 'starter-pack' } | Should -HaveCount $result.Count
    }

    It 'Should load the mobile app preset templates' {
        $result = Get-HydrationWinGetAppTemplates -TemplatePath $script:WinGetTemplatePath -PresetId 'mobile-apps'

        $result.Count | Should -BeGreaterThan 5
        $result.templateId | Should -Not -Contain 'adobe-acrobat-reader-dc'
        $result.templateId | Should -Not -Contain 'powershell'
        $result.templateId | Should -Contain 'microsoft-edge'
        $result.templateId | Should -Contain 'visual-studio-code'
        $result.templateId | Should -Contain 'windows-terminal'
        $result | Where-Object { $_.PresetId -eq 'mobile-apps' } | Should -HaveCount $result.Count
    }

    It 'Should load specific template IDs without a preset' {
        $result = Get-HydrationWinGetAppTemplates -TemplatePath $script:WinGetTemplatePath -TemplateId @('google-chrome', 'putty')

        $result | Should -HaveCount 2
        @($result.templateId) | Should -Contain 'google-chrome'
        @($result.templateId) | Should -Contain 'putty'
    }

    It 'Should resolve requested template IDs case-insensitively' {
        $result = Get-HydrationWinGetAppTemplates -TemplatePath $script:WinGetTemplatePath -TemplateId @('Google-Chrome', 'PuTTY')

        $result | Should -HaveCount 2
        @($result.templateId) | Should -Contain 'google-chrome'
        @($result.templateId) | Should -Contain 'putty'
    }

    It 'Should throw when the preset does not exist' {
        {
            Get-HydrationWinGetAppTemplates -TemplatePath $script:WinGetTemplatePath -PresetId 'missing-preset'
        } | Should -Throw '*missing-preset*'
    }

    It 'Should throw when a requested template does not exist' {
        {
            Get-HydrationWinGetAppTemplates -TemplatePath $script:WinGetTemplatePath -TemplateId 'does-not-exist'
        } | Should -Throw '*does-not-exist*'
    }

    It 'Should return no templates when the default bundled catalog is not present' {
        $script:TemplatesPath = Join-Path ([System.IO.Path]::GetTempPath()) "MissingTemplates-$([guid]::NewGuid().ToString('N'))"

        $result = Get-HydrationWinGetAppTemplates

        $result | Should -BeNullOrEmpty
    }
}
