#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Resolve-WinGetAppIcon.ps1
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..'
}

Describe 'Resolve-WinGetAppIcon' {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'winget-icon'
        $null = New-Item -Path $script:testRoot -ItemType Directory -Force
    }

    It 'Should resolve an icon from a template-relative file path' {
        $iconPath = Join-Path $script:testRoot 'icon.png'
        [System.IO.File]::WriteAllBytes($iconPath, [byte[]](1, 2, 3, 4))

        $template = [pscustomobject]@{
            templateId        = 'contoso-app'
            packageIdentifier = 'Contoso.App'
            displayName       = 'Contoso App'
            TemplatePath      = Join-Path $script:testRoot 'contoso-app.json'
            icon              = [pscustomobject]@{
                sourceType = 'file'
                fileName   = 'icon.png'
            }
        }

        $result = Resolve-WinGetAppIcon -Template $template

        $result.Base64 | Should -Be ([Convert]::ToBase64String([byte[]](1, 2, 3, 4)))
        $result.MimeType | Should -Be 'image/png'
        $result.Source | Should -Be $iconPath
    }

    It 'Should fall back to the bundled module icon when no template file icon can be resolved' {
        $fallbackIconPath = Join-Path $script:ModuleRoot 'media/IHTLogoClearLight.png'
        $fallbackBytes = [System.IO.File]::ReadAllBytes($fallbackIconPath)

        $template = [pscustomobject]@{
            templateId        = 'unavailable-app'
            packageIdentifier = 'Contoso.Unavailable'
            displayName       = 'Unavailable App'
            TemplatePath      = Join-Path $script:testRoot 'unavailable-app.json'
            icon              = [pscustomobject]@{
                sourceType = 'file'
                fileName   = 'missing.png'
            }
        }

        $result = Resolve-WinGetAppIcon -Template $template

        $result.Base64 | Should -Be ([Convert]::ToBase64String($fallbackBytes))
        $result.MimeType | Should -Be 'image/png'
        $result.Source | Should -Be $fallbackIconPath
    }

    It 'Should treat no icon as an expected fallback path' {
        $fallbackIconPath = Join-Path $script:ModuleRoot 'media/IHTLogoClearLight.png'
        $fallbackBytes = [System.IO.File]::ReadAllBytes($fallbackIconPath)

        $template = [pscustomobject]@{
            templateId        = 'no-icon-app'
            packageIdentifier = 'Contoso.NoIcon'
            displayName       = 'No Icon App'
            TemplatePath      = Join-Path $script:testRoot 'no-icon-app.json'
            icon              = [pscustomobject]@{
                sourceType = 'none'
            }
        }

        $result = Resolve-WinGetAppIcon -Template $template

        $result.Base64 | Should -Be ([Convert]::ToBase64String($fallbackBytes))
        $result.Source | Should -Be $fallbackIconPath
    }
}
