#Requires -Modules Pester

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $moduleRoot -ChildPath 'IntuneHydrationKit.psd1'
    $helpersPath = Join-Path -Path $moduleRoot -ChildPath 'Scripts/Modules/Helpers.psm1'

    # Import modules
    Import-Module -Name $modulePath -Force
    Import-Module -Name $helpersPath -Force
}

Describe 'Module Import Tests' {
    It 'Should import IntuneHydrationKit module without errors' {
        { Import-Module -Name $modulePath -Force } | Should -Not -Throw
    }

    It 'Should import Helpers module without errors' {
        { Import-Module -Name $helpersPath -Force } | Should -Not -Throw
    }

    It 'Should export expected functions' {
        $expectedFunctions = @(
            'Invoke-IntuneHydration',
            'Connect-IntuneHydration',
            'Test-IntunePrerequisites',
            'New-IntuneDynamicGroup',
            'Get-OpenIntuneBaseline',
            'Import-IntuneBaseline',
            'Import-IntuneEnrollmentProfile',
            'Import-IntuneDeviceFilter',
            'Import-IntuneConditionalAccessPolicy',
            'Get-HydrationSummary'
        )

        $exportedFunctions = (Get-Module IntuneHydrationKit).ExportedFunctions.Keys

        foreach ($func in $expectedFunctions) {
            $exportedFunctions | Should -Contain $func
        }
    }
}

Describe 'Helper Function Tests' {
    Context 'Get-TemplateFiles' {
        It 'Should return JSON files from a directory' {
            $templatesPath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups'
            $files = Get-TemplateFiles -Path $templatesPath

            $files | Should -Not -BeNullOrEmpty
            $files | ForEach-Object { $_.Extension | Should -Be '.json' }
        }
    }

    Context 'Import-TemplateFile' {
        It 'Should load and parse a JSON template' {
            $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups/OS-Groups.json'

            if (Test-Path $templatePath) {
                $template = Import-TemplateFile -Path $templatePath

                $template | Should -Not -BeNullOrEmpty
                $template.groups | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Get-UpsertDecision' {
        It 'Should return Create when no existing resource' {
            $newResource = @{ displayName = 'Test' }
            $decision = Get-UpsertDecision -NewResource $newResource

            $decision.Action | Should -Be 'Create'
        }

        It 'Should return Update when ForceUpdate is specified' {
            $existing = @{ id = '123'; displayName = 'Test' }
            $new = @{ displayName = 'Test' }
            $decision = Get-UpsertDecision -ExistingResource $existing -NewResource $new -ForceUpdate

            $decision.Action | Should -Be 'Update'
        }

        It 'Should return Skip when resources are identical' {
            $resource = @{ displayName = 'Test'; value = 1 }
            $decision = Get-UpsertDecision -ExistingResource $resource -NewResource $resource

            $decision.Action | Should -Be 'Skip'
        }
    }

    Context 'New-HydrationResult' {
        It 'Should create a valid result object' {
            $result = New-HydrationResult -Type 'DynamicGroup' -Name 'Test Group' -Action 'Created' -Id '123'

            $result.Type | Should -Be 'DynamicGroup'
            $result.Name | Should -Be 'Test Group'
            $result.Action | Should -Be 'Created'
            $result.Id | Should -Be '123'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-ResultSummary' {
        It 'Should summarize results correctly' {
            $results = @(
                [PSCustomObject]@{ Type = 'Group'; Action = 'Created' }
                [PSCustomObject]@{ Type = 'Group'; Action = 'Created' }
                [PSCustomObject]@{ Type = 'Policy'; Action = 'Skipped' }
                [PSCustomObject]@{ Type = 'Policy'; Action = 'Failed' }
            )

            $summary = Get-ResultSummary -Results $results

            $summary.Total | Should -Be 4
            $summary.Created | Should -Be 2
            $summary.Skipped | Should -Be 1
            $summary.Failed | Should -Be 1
        }
    }
}

Describe 'Template Validation Tests' {
    Context 'Dynamic Group Templates' {
        It 'Should have valid OS group templates' {
            $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups/OS-Groups.json'

            Test-Path $templatePath | Should -BeTrue

            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            $template.groups | Should -Not -BeNullOrEmpty
            $template.groups.Count | Should -BeGreaterThan 0

            foreach ($group in $template.groups) {
                $group.displayName | Should -Not -BeNullOrEmpty
                $group.membershipRule | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should have valid manufacturer group templates' {
            $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups/Manufacturer-Groups.json'

            Test-Path $templatePath | Should -BeTrue

            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            $template.groups | Should -Not -BeNullOrEmpty
        }

        It 'Should have valid Autopilot group templates' {
            $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups/Autopilot-Groups.json'

            Test-Path $templatePath | Should -BeTrue

            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            $template.groups | Should -Not -BeNullOrEmpty
        }

        It 'Should have valid compliance group templates' {
            $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/DynamicGroups/Compliance-Groups.json'

            Test-Path $templatePath | Should -BeTrue

            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            $template.groups | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Enrollment Templates' {
        It 'Should have valid Autopilot profile template' {
            $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/Enrollment/Windows-Autopilot-Profile.json'

            Test-Path $templatePath | Should -BeTrue

            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            $template.displayName | Should -Not -BeNullOrEmpty
            $template.outOfBoxExperienceSettings | Should -Not -BeNullOrEmpty
        }

        It 'Should have valid ESP profile template' {
            $templatePath = Join-Path -Path $moduleRoot -ChildPath 'Templates/Enrollment/Windows-ESP-Profile.json'

            Test-Path $templatePath | Should -BeTrue

            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            $template.displayName | Should -Not -BeNullOrEmpty
            $template.showInstallationProgress | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Conditional Access Templates' {
        It 'Should have CA policy templates' {
            $templatesPath = Join-Path -Path $moduleRoot -ChildPath 'Templates/ConditionalAccess'

            Test-Path $templatesPath | Should -BeTrue

            $templates = Get-ChildItem -Path $templatesPath -Filter '*.json'
            $templates.Count | Should -BeGreaterThan 0
        }

        It 'Should have valid CA policy structure' {
            $templatesPath = Join-Path -Path $moduleRoot -ChildPath 'Templates/ConditionalAccess'
            $templates = Get-ChildItem -Path $templatesPath -Filter '*.json'

            foreach ($templateFile in $templates) {
                $template = Get-Content $templateFile.FullName -Raw | ConvertFrom-Json

                $template.displayName | Should -Not -BeNullOrEmpty -Because "Template $($templateFile.Name) should have displayName"
                $template.conditions | Should -Not -BeNullOrEmpty -Because "Template $($templateFile.Name) should have conditions"
            }
        }
    }
}

Describe 'Settings Validation Tests' {
    Context 'Settings Schema' {
        It 'Should have example settings file' {
            $settingsPath = Join-Path -Path $moduleRoot -ChildPath 'settings.example.json'

            Test-Path $settingsPath | Should -BeTrue
        }

        It 'Should have valid settings structure' {
            $settingsPath = Join-Path -Path $moduleRoot -ChildPath 'settings.example.json'
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

            $settings.tenant | Should -Not -BeNullOrEmpty
            $settings.tenant.tenantId | Should -Not -BeNullOrEmpty
            $settings.authentication | Should -Not -BeNullOrEmpty
            $settings.imports | Should -Not -BeNullOrEmpty
            $settings.reporting | Should -Not -BeNullOrEmpty
        }

        It 'Should have all required import toggles' {
            $settingsPath = Join-Path -Path $moduleRoot -ChildPath 'settings.example.json'
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

            $settings.imports.openIntuneBaseline | Should -Not -BeNullOrEmpty
            $settings.imports.enrollmentProfiles | Should -Not -BeNullOrEmpty
            $settings.imports.dynamicGroups | Should -Not -BeNullOrEmpty
            $settings.imports.conditionalAccess | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Function Parameter Tests' {
    Context 'Connect-IntuneHydration' {
        It 'Should have TenantId as mandatory parameter' {
            $command = Get-Command Connect-IntuneHydration
            $param = $command.Parameters['TenantId']

            $param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have Environment parameter with valid values' {
            $command = Get-Command Connect-IntuneHydration
            $param = $command.Parameters['Environment']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Global'
            $validateSet.ValidValues | Should -Contain 'USGov'
            $validateSet.ValidValues | Should -Contain 'USGovDoD'
        }
    }

    Context 'Import-IntuneBaseline' {
        It 'Should have ImportMode parameter with valid values' {
            $command = Get-Command Import-IntuneBaseline
            $param = $command.Parameters['ImportMode']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'AlwaysImport'
            $validateSet.ValidValues | Should -Contain 'SkipIfExists'
            $validateSet.ValidValues | Should -Contain 'Replace'
            $validateSet.ValidValues | Should -Contain 'Update'
        }
    }

    Context 'New-IntuneDynamicGroup' {
        It 'Should have DisplayName as mandatory parameter' {
            $command = Get-Command New-IntuneDynamicGroup
            $param = $command.Parameters['DisplayName']

            $param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have MembershipRule as mandatory parameter' {
            $command = Get-Command New-IntuneDynamicGroup
            $param = $command.Parameters['MembershipRule']

            $param.Attributes.Mandatory | Should -Contain $true
        }
    }
}

Describe 'Module Manifest Tests' {
    It 'Should have valid module manifest' {
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'IntuneHydrationKit.psd1'

        { Test-ModuleManifest -Path $manifestPath } | Should -Not -Throw
    }

    It 'Should have correct PowerShell version requirement' {
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'IntuneHydrationKit.psd1'
        $manifest = Test-ModuleManifest -Path $manifestPath

        $manifest.PowerShellVersion | Should -Be '7.0'
    }

    It 'Should have required modules specified' {
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'IntuneHydrationKit.psd1'
        $manifest = Test-ModuleManifest -Path $manifestPath

        $manifest.RequiredModules | Should -Not -BeNullOrEmpty
    }

    It 'Should have module description' {
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'IntuneHydrationKit.psd1'
        $manifest = Test-ModuleManifest -Path $manifestPath

        $manifest.Description | Should -Not -BeNullOrEmpty
    }
}
