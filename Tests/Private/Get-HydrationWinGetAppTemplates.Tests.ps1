#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\WinGet\Get-HydrationWinGetAppTemplates.ps1'
    . $functionPath

    $script:RepoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:TemplatesPath = Join-Path -Path $script:RepoRoot -ChildPath 'Templates'
    $script:WinGetTemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath 'MobileApps/Windows/WinGet'
}

Describe 'Get-HydrationWinGetAppTemplates' {
    It 'Should load the starter pack preset templates' {
        $result = Get-HydrationWinGetAppTemplates -PresetId 'starter-pack'

        $result.Count | Should -BeGreaterThan 5
        $result.templateId | Should -Contain '7-zip'
        $result.templateId | Should -Contain 'notepad-plus-plus'
        $result.templateId | Should -Contain 'vlc-media-player'
        $result | Where-Object { $_.PresetId -eq 'starter-pack' } | Should -HaveCount $result.Count
    }

    It 'Should load the mobile app preset templates' {
        $result = Get-HydrationWinGetAppTemplates -PresetId 'mobile-apps'

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
}
