#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Baselines/Get-BaselineImportMetadata.ps1
    . $PSScriptRoot/../../Private/Baselines/Resolve-CISBaselineTemplatePlatform.ps1
}

Describe 'Resolve-CISBaselineTemplatePlatform' {
    BeforeAll {
        $script:platformMap = (Get-BaselineImportMetadata -Kind 'CIS').PlatformValueMapping

        function New-CISTestTemplate {
            param(
                [Parameter(Mandatory)]
                [string]$RelativePath,

                [Parameter(Mandatory)]
                [hashtable]$Content
            )

            $baseDir = Join-Path 'TestDrive:' 'CISResolver'
            $fullPath = Join-Path $baseDir $RelativePath
            New-Item -Path (Split-Path -Parent $fullPath) -ItemType Directory -Force | Out-Null
            Set-Content -Path $fullPath -Value ($Content | ConvertTo-Json -Depth 8)
            return [pscustomobject]@{
                BaseDir = $baseDir
                File    = Get-Item -Path $fullPath
            }
        }
    }

    It 'Should prefer explicit platforms metadata' {
        $template = New-CISTestTemplate -RelativePath 'Ambiguous/Policy.json' -Content @{
            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy'
            name          = 'Ambiguous policy'
            platforms     = @('androidEnterprise', 'windows10')
        }

        $result = Resolve-CISBaselineTemplatePlatform -TemplateContent (Get-Content -Raw $template.File.FullName | ConvertFrom-Json) -TemplateFile $template.File -BaselinePath $template.BaseDir -PlatformValueMapping $script:platformMap

        $result | Should -Contain 'Android'
        $result | Should -Contain 'Windows'
    }

    It 'Should resolve platform from compliance odata type when platforms metadata is absent' {
        $template = New-CISTestTemplate -RelativePath 'Apple MacOS Compliance/Mac.json' -Content @{
            '@odata.type' = '#microsoft.graph.macOSCompliancePolicy'
            displayName   = 'macOS Compliance Without Platforms'
        }

        $result = Resolve-CISBaselineTemplatePlatform -TemplateContent (Get-Content -Raw $template.File.FullName | ConvertFrom-Json) -TemplateFile $template.File -BaselinePath $template.BaseDir -PlatformValueMapping $script:platformMap

        $result | Should -Be @('macOS')
    }

    It 'Should resolve current bundled Windows no-platform intent and configuration hints' {
        $cases = @(
            @{
                RelativePath = '6.0 - Microsoft Endpoint Security Benchmarks/Microsoft Defender for Endpoint/Baseline - MDE Device Tag.json'
                Content      = @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    displayName   = 'Baseline - MDE Device Tag'
                }
            }
            @{
                RelativePath = '6.0 - Microsoft Endpoint Security Benchmarks/Bitlocker en Personal Data Encryption/Baseline - Bitlocker Policy.json'
                Content      = @{
                    '@odata.type' = '#microsoft.graph.deviceManagementIntent'
                    displayName   = 'Baseline - Bitlocker Policy'
                }
            }
            @{
                RelativePath = '6.0 - Microsoft Endpoint Security Benchmarks/Endpoint Protection/Baseline - Account Protection.json'
                Content      = @{
                    '@odata.type' = '#microsoft.graph.deviceManagementIntent'
                    displayName   = 'Baseline - Account Protection'
                }
            }
        )

        foreach ($case in $cases) {
            $template = New-CISTestTemplate -RelativePath $case.RelativePath -Content $case.Content
            $result = Resolve-CISBaselineTemplatePlatform -TemplateContent (Get-Content -Raw $template.File.FullName | ConvertFrom-Json) -TemplateFile $template.File -BaselinePath $template.BaseDir -PlatformValueMapping $script:platformMap

            $result | Should -Be @('Windows')
        }
    }

    It 'Should resolve macOS before generic firewall Windows hints' {
        $template = New-CISTestTemplate -RelativePath '6.0 - Microsoft Endpoint Security Benchmarks/Firewall/Baseline - MacOS - Firewall.json' -Content @{
            '@odata.type' = '#microsoft.graph.deviceManagementIntent'
            displayName   = 'Baseline - MacOS - Firewall'
        }

        $result = Resolve-CISBaselineTemplatePlatform -TemplateContent (Get-Content -Raw $template.File.FullName | ConvertFrom-Json) -TemplateFile $template.File -BaselinePath $template.BaseDir -PlatformValueMapping $script:platformMap

        $result | Should -Be @('macOS')
    }
}
