#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Get-TemplateDisplayNames.ps1
}

Describe 'Get-TemplateDisplayNames' {
    Context 'Basic displayName extraction' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-Basic-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            @{ displayName = 'Policy Alpha' } | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'alpha.json')
            @{ displayName = 'Policy Beta' }  | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'beta.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should extract displayName from each JSON file' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -HaveCount 2
            $result | Should -Contain 'Policy Alpha'
            $result | Should -Contain 'Policy Beta'
        }

        It 'Should return string values from a HashSet' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -BeOfType 'string'
        }
    }

    Context 'Fallback to name property' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-Fallback-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            @{ name = 'Config Policy One' } | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'one.json')
            @{ displayName = 'Config Policy Two' } | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'two.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should fall back to name when displayName is absent' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -Contain 'Config Policy One'
        }

        It 'Should prefer displayName when present' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -Contain 'Config Policy Two'
        }
    }

    Context 'Explicit NameProperty parameter' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-NameProp-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            @{ name = 'Named Policy'; displayName = 'Display Policy' } | ConvertTo-Json |
                Set-Content (Join-Path $script:tempDir 'policy.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should use specified NameProperty instead of displayName' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir -NameProperty 'name'
            $result | Should -Contain 'Named Policy'
            $result | Should -Not -Contain 'Display Policy'
        }
    }

    Context 'ArrayProperty mode' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-Array-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            $template = @{
                filters = @(
                    @{ displayName = 'Filter One' }
                    @{ displayName = 'Filter Two' }
                )
            }
            $template | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:tempDir 'filters.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should extract names from nested array elements' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir -ArrayProperty 'filters'
            $result | Should -HaveCount 2
            $result | Should -Contain 'Filter One'
            $result | Should -Contain 'Filter Two'
        }
    }

    Context 'UseFileName mode' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-FileName-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            '{}' | Set-Content (Join-Path $script:tempDir 'Require-MFA.json')
            '{}' | Set-Content (Join-Path $script:tempDir 'Block-Legacy.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should use file basenames as names' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir -UseFileName
            $result | Should -HaveCount 2
            $result | Should -Contain 'Require-MFA'
            $result | Should -Contain 'Block-Legacy'
        }

        It 'Should prepend prefix to file basenames when Prefix is specified' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir -UseFileName -Prefix 'CA - '
            $result | Should -HaveCount 2
            $result | Should -Contain 'CA - Require-MFA'
            $result | Should -Contain 'CA - Block-Legacy'
        }
    }

    Context 'Recurse parameter' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-Recurse-$([guid]::NewGuid().ToString('N'))"
            $subDir = Join-Path $script:tempDir 'SubFolder'
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null

            @{ displayName = 'Root Policy' } | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'root.json')
            @{ displayName = 'Sub Policy' }  | ConvertTo-Json | Set-Content (Join-Path $subDir 'sub.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should find files in subdirectories when Recurse is specified' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir -Recurse
            $result | Should -HaveCount 2
            $result | Should -Contain 'Root Policy'
            $result | Should -Contain 'Sub Policy'
        }

        It 'Should not find subdirectory files without Recurse' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -HaveCount 1
            $result | Should -Contain 'Root Policy'
        }
    }

    Context 'Empty and missing paths' {
        BeforeAll {
            $script:emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-Empty-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:emptyDir -ItemType Directory -Force | Out-Null
        }

        AfterAll {
            Remove-Item -Path $script:emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should return empty HashSet for nonexistent path' {
            $result = Get-TemplateDisplayNames -Path 'C:\NonExistent\Path\12345'
            $result | Should -HaveCount 0
        }

        It 'Should return empty HashSet for directory with no JSON files' {
            $result = Get-TemplateDisplayNames -Path $script:emptyDir
            $result | Should -HaveCount 0
        }
    }

    Context 'Case insensitivity and deduplication' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-CaseDup-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            @{ displayName = 'My Policy' }   | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'a.json')
            @{ displayName = 'MY POLICY' }   | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'b.json')
            @{ displayName = 'my policy' }   | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'c.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should deduplicate case-insensitively' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -HaveCount 1
        }

        It 'Should contain the name regardless of case used for lookup' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -Contain 'MY POLICY'
            $result | Should -Contain 'my policy'
            $result | Should -Contain 'My Policy'
        }
    }

    Context 'Invalid JSON files' {
        BeforeAll {
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "GtdnTest-Invalid-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            'this is not valid json {{{' | Set-Content (Join-Path $script:tempDir 'bad.json')
            @{ displayName = 'Good Policy' } | ConvertTo-Json | Set-Content (Join-Path $script:tempDir 'good.json')
        }

        AfterAll {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should skip invalid JSON and return valid entries' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir
            $result | Should -HaveCount 1
            $result | Should -Contain 'Good Policy'
        }

        It 'Should produce verbose output for invalid JSON' {
            $result = Get-TemplateDisplayNames -Path $script:tempDir -Verbose 4>&1
            $verboseMessages = $result | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages.Message | Should -Contain 'Failed to parse template: bad.json'
        }
    }
}
