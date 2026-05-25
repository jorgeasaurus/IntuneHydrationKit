#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:WinGetTemplateRoot = Join-Path -Path $script:RepoRoot -ChildPath 'Templates/MobileApps/Windows/WinGet'
    $script:WinGetTemplateSchema = Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Schemas/winGetAppTemplate.schema.json'
    $script:WinGetPresetSchema = Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Schemas/winGetAppPreset.schema.json'
    $script:WinGetAppTemplates = Get-ChildItem -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Apps') -Filter '*.json' -File
    $script:WinGetPresets = Get-ChildItem -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Presets') -Filter '*.json' -File
}

Describe 'WinGet starter-pack template contracts' {
    It 'Should keep WinGet app templates valid against the repo schema' {
        $script:WinGetAppTemplates.Count | Should -BeGreaterThan 0

        foreach ($templateFile in $script:WinGetAppTemplates) {
            Test-Json -Path $templateFile.FullName -SchemaFile $script:WinGetTemplateSchema | Should -BeTrue -Because $templateFile.FullName
        }
    }

    It 'Should keep repo-owned WinGet detection script files out of the app templates directory' {
        $detectionScripts = Get-ChildItem -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Apps') -Filter '*-detection.ps1' -File

        $detectionScripts | Should -BeNullOrEmpty
    }

    It 'Should keep WinGet app icons on the current file-or-none contract' {
        foreach ($templateFile in $script:WinGetAppTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

            $template.icon.PSObject.Properties.Name | Should -Not -Contain 'sourceUri' -Because $templateFile.FullName
            $template.icon.sourceType | Should -BeIn @('file', 'none') -Because $templateFile.FullName
        }
    }

    It 'Should keep WinGet presets valid against the repo schema' {
        $script:WinGetPresets.Count | Should -BeGreaterThan 0

        foreach ($presetFile in $script:WinGetPresets) {
            Test-Json -Path $presetFile.FullName -SchemaFile $script:WinGetPresetSchema | Should -BeTrue -Because $presetFile.FullName
        }
    }

    It 'Should keep the starter pack aligned with its referenced template files' {
        $preset = Get-Content -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Presets/starter-pack.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
        $templateIds = $script:WinGetAppTemplates.BaseName

        foreach ($appId in $preset.appIds) {
            $templateIds | Should -Contain $appId
        }
    }

    It 'Should keep the mobile app preset aligned with its referenced template files' {
        $preset = Get-Content -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Presets/mobile-apps.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
        $templateIds = $script:WinGetAppTemplates.BaseName

        foreach ($appId in $preset.appIds) {
            $templateIds | Should -Contain $appId
        }
    }

    It 'Should retain Microsoft Edge in the mobile app preset' {
        $preset = Get-Content -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Presets/mobile-apps.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

        $preset.appIds | Should -Contain 'microsoft-edge'
    }

    It 'Should retain the IntuneAppFactory-overlap apps in the starter pack' {
        $preset = Get-Content -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Presets/starter-pack.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

        $preset.appIds | Should -Contain '7-zip'
        $preset.appIds | Should -Contain 'notepad-plus-plus'
        $preset.appIds | Should -Contain 'vlc-media-player'
    }

    It 'Should retain Claude apps in the starter pack' {
        $preset = Get-Content -Path (Join-Path -Path $script:WinGetTemplateRoot -ChildPath 'Presets/starter-pack.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

        $preset.appIds | Should -Contain 'claude'
        $preset.appIds | Should -Contain 'claude-code'
    }

    It 'Should keep WinGet app templates on generated detection' {
        foreach ($templateFile in $script:WinGetAppTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
            $template.detection.strategy | Should -Be 'generated' -Because $templateFile.FullName
        }
    }

    It 'Should keep bundled WinGet app templates on resolved package metadata' {
        foreach ($templateFile in $script:WinGetAppTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

            $template.resolvedPackage.manifestSource.repository | Should -Be 'microsoft/winget-pkgs' -Because $templateFile.FullName
            $template.resolvedPackage.selectedInstaller.Architecture | Should -BeIn $template.package.match.architectures -Because $templateFile.FullName
            $template.resolvedPackage.selectedInstaller.Scope | Should -Be $template.package.match.scope -Because $templateFile.FullName
            if ($null -ne $template.package.match.locale) {
                $template.resolvedPackage.selectedInstaller.InstallerLocale | Should -Be $template.package.match.locale -Because $templateFile.FullName
            }
            $template.resolvedPackage.selectedInstaller.InstallerType | Should -BeIn $template.package.match.installerTypes -Because $templateFile.FullName
        }
    }

    It 'Should enforce the declared WinGet scope in install and uninstall commands' {
        foreach ($templateFile in $script:WinGetAppTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
            $scope = $template.package.match.scope

            if (-not [string]::IsNullOrWhiteSpace($scope)) {
                $template.install.command | Should -Match "--scope $scope(\s|$)" -Because $templateFile.FullName
                $template.uninstall.command | Should -Match "--scope $scope(\s|$)" -Because $templateFile.FullName
            }
        }
    }

    It 'Should keep file-backed WinGet app icons resolvable' {
        foreach ($templateFile in $script:WinGetAppTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

            if ($template.icon.sourceType -eq 'file') {
                $iconPath = Join-Path -Path $templateFile.DirectoryName -ChildPath $template.icon.fileName
                Test-Path -Path $iconPath -PathType Leaf | Should -BeTrue -Because $templateFile.FullName

                if ([System.IO.Path]::GetExtension($iconPath) -eq '.png') {
                    $iconBytes = [System.IO.File]::ReadAllBytes($iconPath)
                    $iconBytes.Length | Should -BeGreaterThan 8 -Because $templateFile.FullName
                    $iconBytes[0..7] | Should -Be @(137, 80, 78, 71, 13, 10, 26, 10) -Because $templateFile.FullName
                }
            }
        }
    }
}
