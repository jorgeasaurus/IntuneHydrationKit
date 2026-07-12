#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Templates\Get-HydrationTemplates.ps1'
    . $functionPath
}

Describe 'Get-HydrationTemplates' {
    Context 'When directory contains JSON files' {
        BeforeAll {
            New-Item -Path "TestDrive:\templates" -ItemType Directory -Force
            '{}' | Set-Content -Path "TestDrive:\templates\policy1.json"
            '{}' | Set-Content -Path "TestDrive:\templates\policy2.json"
        }

        It 'Should return JSON files from flat directory' {
            $result = Get-HydrationTemplates -Path "TestDrive:\templates"
            $result | Should -HaveCount 2
        }

        It 'Should return FileInfo objects' {
            $result = Get-HydrationTemplates -Path "TestDrive:\templates"
            $result[0] | Should -BeOfType [System.IO.FileInfo]
        }
    }

    Context 'When directory contains no JSON files' {
        BeforeAll {
            New-Item -Path "TestDrive:\empty" -ItemType Directory -Force
            'not json' | Set-Content -Path "TestDrive:\empty\readme.txt"
        }

        It 'Should return empty when no JSON files exist' {
            $result = Get-HydrationTemplates -Path "TestDrive:\empty"
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When non-JSON files are present' {
        BeforeAll {
            New-Item -Path "TestDrive:\mixed" -ItemType Directory -Force
            '{}' | Set-Content -Path "TestDrive:\mixed\template.json"
            'text' | Set-Content -Path "TestDrive:\mixed\readme.md"
            'xml' | Set-Content -Path "TestDrive:\mixed\config.xml"
            'ps1' | Set-Content -Path "TestDrive:\mixed\script.ps1"
        }

        It 'Should exclude non-JSON files' {
            $result = Get-HydrationTemplates -Path "TestDrive:\mixed"
            $result | Should -HaveCount 1
            $result[0].Name | Should -Be 'template.json'
        }
    }

    Context 'Recurse switch' {
        BeforeAll {
            New-Item -Path "TestDrive:\nested\sub1" -ItemType Directory -Force
            New-Item -Path "TestDrive:\nested\sub2" -ItemType Directory -Force
            '{}' | Set-Content -Path "TestDrive:\nested\root.json"
            '{}' | Set-Content -Path "TestDrive:\nested\sub1\child1.json"
            '{}' | Set-Content -Path "TestDrive:\nested\sub2\child2.json"
        }

        It 'Should not recurse by default' {
            $result = Get-HydrationTemplates -Path "TestDrive:\nested"
            $result | Should -HaveCount 1
            $result[0].Name | Should -Be 'root.json'
        }

        It 'Should find nested files with -Recurse' {
            $result = Get-HydrationTemplates -Path "TestDrive:\nested" -Recurse
            $result | Should -HaveCount 3
        }
    }

    Context 'When directory is empty' {
        BeforeAll {
            New-Item -Path "TestDrive:\emptydir" -ItemType Directory -Force
        }

        It 'Should return empty for empty directory' {
            $result = Get-HydrationTemplates -Path "TestDrive:\emptydir"
            $result | Should -BeNullOrEmpty
        }
    }
}
