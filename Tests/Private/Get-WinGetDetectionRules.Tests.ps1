#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-WinGetDetectionRules.ps1
}

Describe 'Get-WinGetDetectionRules' {
    It 'Should use generated script detection even when WinGet manifest metadata has an MSI product code' {
        $template = [pscustomobject]@{
            templateId = 'google-chrome'
            detection  = [pscustomobject]@{
                strategy = 'generated'
            }
        }

        $packageMetadata = [pscustomobject]@{
            SelectedInstaller = [pscustomobject]@{
                InstallerType = 'msi'
                ProductCode   = '{042C29DE-2EAE-34E1-A978-C2BE5AB65557}'
            }
        }

        $result = Get-WinGetDetectionRules -Template $template -PackageMetadata $packageMetadata

        $rules = @($result)
        $rules | Should -HaveCount 1
        $rules[0].DetectionType | Should -Be 'Script'
        $rules[0].ScriptFile | Should -Be 'Detect-WinGetPackage.ps1'
    }

    It 'Should reject unsupported WinGet detection strategies' {
        $template = [pscustomobject]@{
            templateId = 'contoso-app'
            detection  = [pscustomobject]@{
                strategy = 'msi'
            }
        }

        { Get-WinGetDetectionRules -Template $template } | Should -Throw "*Detection strategy 'msi' is not supported*"
    }
}
