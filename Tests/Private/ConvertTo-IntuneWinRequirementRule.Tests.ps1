#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Utilities/ConvertTo-HydrationBoolValue.ps1
    . $PSScriptRoot/../../Private/WinGet/ConvertTo-IntuneWinRequirementRule.ps1
}

Describe 'ConvertTo-IntuneWinRequirementRule' {
    BeforeAll {
        $script:artifactRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/ConvertTo-IntuneWinRequirementRule'
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }

        $null = New-Item -Path $script:artifactRoot -ItemType Directory -Force
        'Write-Output 1' | Set-Content -Path (Join-Path $script:artifactRoot 'requirement.ps1')
    }

    AfterAll {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
    }

    It 'Should map registry requirement rules' {
        $result = ConvertTo-IntuneWinRequirementRule -Rule ([pscustomobject]@{
                RequirementType = 'Registry'
                KeyPath         = 'HKLM:\Software\Contoso'
                ValueName       = 'DisplayVersion'
                Value           = '2.0'
            })

        $result['@odata.type'] | Should -Be '#microsoft.graph.win32LobAppRegistryRequirement'
        $result.operationType | Should -Be 'version'
        $result.detectionValue | Should -Be '2.0'
    }

    It 'Should map script requirement rules' {
        $result = ConvertTo-IntuneWinRequirementRule -Rule ([pscustomobject]@{
                RequirementType       = 'Script'
                ScriptFile            = 'requirement.ps1'
                Value                 = '1'
                EnforceSignatureCheck = 'false'
                RunAs32Bit            = 'false'
            }) -ScriptRootPath $script:artifactRoot

        $decodedScript = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($result.scriptContent))
        $decodedScript | Should -Match 'Write-Output 1'
        $result.detectionValue | Should -Be '1'
    }

    It 'Should throw for unsupported requirement rules' {
        { ConvertTo-IntuneWinRequirementRule -Rule ([pscustomobject]@{ RequirementType = 'Unsupported' }) } | Should -Throw '*Unsupported requirement rule type*'
    }

    It 'Should throw for unrecognized boolean strings' {
        {
            ConvertTo-IntuneWinRequirementRule -Rule ([pscustomobject]@{
                    RequirementType       = 'Script'
                    ScriptFile            = 'requirement.ps1'
                    Value                 = '1'
                    EnforceSignatureCheck = 'maybe'
                    RunAs32Bit            = 'false'
                }) -ScriptRootPath $script:artifactRoot
        } | Should -Throw "*Unsupported boolean string value: 'maybe'*"
    }

    It 'Should throw a clear error when script root path is missing for script rules' {
        {
            ConvertTo-IntuneWinRequirementRule -Rule ([pscustomobject]@{
                    RequirementType = 'Script'
                    ScriptFile      = 'requirement.ps1'
                    Value           = '1'
                })
        } | Should -Throw "*ScriptRootPath is required for script requirement rule 'requirement.ps1'*"
    }
}
