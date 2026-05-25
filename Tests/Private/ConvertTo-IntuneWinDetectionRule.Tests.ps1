#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Utilities/ConvertTo-HydrationBoolValue.ps1
    . $PSScriptRoot/../../Private/WinGet/ConvertTo-IntuneWinDetectionRule.ps1
}

Describe 'ConvertTo-IntuneWinDetectionRule' {
    BeforeAll {
        $script:artifactRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/ConvertTo-IntuneWinDetectionRule'
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }

        $null = New-Item -Path $script:artifactRoot -ItemType Directory -Force
        'Write-Output ''detected''' | Set-Content -Path (Join-Path $script:artifactRoot 'detection.ps1')
    }

    AfterAll {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
    }

    It 'Should map MSI product code rules' {
        $result = ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{
                DetectionType          = 'MSI'
                ProductCode            = '{1234-5678}'
                ProductVersionOperator = 'greaterThanOrEqual'
                ProductVersion         = '1.2.3'
            })

        $result['@odata.type'] | Should -Be '#microsoft.graph.win32LobAppProductCodeRule'
        $result.productCode | Should -Be '{1234-5678}'
        $result.productVersion | Should -Be '1.2.3'
    }

    It 'Should map registry comparison rules' {
        $result = ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{
                DetectionType        = 'Registry'
                DetectionMethod      = 'VersionComparison'
                KeyPath              = 'HKLM:\Software\Contoso'
                ValueName            = 'DisplayVersion'
                Operator             = 'greaterThanOrEqual'
                Value                = '2.0'
                Check32BitOn64System = 'true'
            })

        $result.operationType | Should -Be 'version'
        $result.comparisonValue | Should -Be '2.0'
        $result.check32BitOn64System | Should -BeTrue
    }

    It 'Should default registry rules to existence when no operation is specified' {
        $result = ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{
                DetectionType = 'Registry'
                KeyPath       = 'HKLM:\Software\Contoso'
            })

        $result.operationType | Should -Be 'exists'
        $result.operator | Should -Be 'notConfigured'
    }

    It 'Should map file existence rules' {
        $result = ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{
                DetectionType     = 'File'
                FileDetectionType = 'exists'
                Path              = 'C:\Program Files\Contoso'
                FileOrFolderName  = 'Contoso.exe'
            })

        $result['@odata.type'] | Should -Be '#microsoft.graph.win32LobAppFileSystemRule'
        $result.operationType | Should -Be 'exists'
        $result.operator | Should -Be 'notConfigured'
    }

    It 'Should default file rules to existence when no operation is specified' {
        $result = ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{
                DetectionType    = 'File'
                Path             = 'C:\Program Files\Contoso'
                FileOrFolderName = 'Contoso.exe'
            })

        $result.operationType | Should -Be 'exists'
        $result.operator | Should -Be 'notConfigured'
    }

    It 'Should base64 encode detection scripts' {
        $result = ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{
                DetectionType         = 'Script'
                ScriptFile            = 'detection.ps1'
                EnforceSignatureCheck = 'false'
                RunAs32Bit            = 'true'
            }) -ScriptRootPath $script:artifactRoot

        $decodedScript = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($result.scriptContent))
        $decodedScript | Should -Match 'detected'
        $result.runAs32Bit | Should -BeTrue
        $result.ContainsKey('runAsAccount') | Should -BeFalse
    }

    It 'Should throw for unsupported rule types' {
        { ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{ DetectionType = 'Unsupported' }) } | Should -Throw '*Unsupported detection rule type*'
    }

    It 'Should throw a clear error when script root path is missing for script rules' {
        {
            ConvertTo-IntuneWinDetectionRule -Rule ([pscustomobject]@{
                    DetectionType = 'Script'
                    ScriptFile    = 'detection.ps1'
                })
        } | Should -Throw "*ScriptRootPath is required for script detection rule 'detection.ps1'*"
    }
}
