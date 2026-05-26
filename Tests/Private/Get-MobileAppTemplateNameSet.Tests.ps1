#Requires -Modules Pester

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..' '..'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $moduleRoot 'IntuneHydrationKit.psd1') -Force
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'Private' 'MobileApps' 'Get-MobileAppTemplateNameSet.ps1'
    . $modulePath
}

Describe 'Get-MobileAppTemplateNameSet' {
    It 'Should extract display names from valid template files' {
        $tempDir = Join-Path $TestDrive 'mobile-app-templates'
        $null = New-Item -Path $tempDir -ItemType Directory -Force
        @'
{
    "displayName": "Company Portal"
}
'@ | Set-Content -Path (Join-Path $tempDir 'CompanyPortal.json') -Encoding utf8
        @'
{
    "displayName": "WhatsApp"
}
'@ | Set-Content -Path (Join-Path $tempDir 'WhatsApp.json') -Encoding utf8

        $files = Get-ChildItem -Path $tempDir -Filter '*.json' -File

        InModuleScope IntuneHydrationKit -Parameters @{ TemplateFiles = $files } {
            $result = Get-MobileAppTemplateNameSet -TemplateFiles $TemplateFiles

            $result | Should -Contain 'Company Portal - [IHD]'
            $result | Should -Contain 'Company Portal'
            $result | Should -Contain '[IHD] Company Portal'
            $result | Should -Contain 'WhatsApp - [IHD]'
        }
    }

    It 'Should skip templates with missing displayName' {
        $tempDir = Join-Path $TestDrive 'mobile-app-templates-missing'
        $null = New-Item -Path $tempDir -ItemType Directory -Force
        @'
{
    "publisher": "Test"
}
'@ | Set-Content -Path (Join-Path $tempDir 'NoName.json') -Encoding utf8

        $files = Get-ChildItem -Path $tempDir -Filter '*.json' -File

        InModuleScope IntuneHydrationKit -Parameters @{ TemplateFiles = $files } {
            $result = Get-MobileAppTemplateNameSet -TemplateFiles $TemplateFiles

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Should skip invalid JSON files' {
        $tempDir = Join-Path $TestDrive 'mobile-app-templates-invalid'
        $null = New-Item -Path $tempDir -ItemType Directory -Force
        'not json' | Set-Content -Path (Join-Path $tempDir 'Bad.json') -Encoding utf8

        $files = Get-ChildItem -Path $tempDir -Filter '*.json' -File

        InModuleScope IntuneHydrationKit -Parameters @{ TemplateFiles = $files } {
            $result = Get-MobileAppTemplateNameSet -TemplateFiles $TemplateFiles

            $result | Should -BeNullOrEmpty
        }
    }
}
