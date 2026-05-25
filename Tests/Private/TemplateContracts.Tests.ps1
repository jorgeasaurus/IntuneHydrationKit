#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
    $script:HydrationModule = Get-Module IntuneHydrationKit

    $script:OpenIntuneTemplates = Get-ChildItem -Path (Join-Path $modulePath 'Templates/OpenIntuneBaseline') -Filter '*.json' -File -Recurse
    $script:CisTemplates = Get-ChildItem -Path (Join-Path $modulePath 'Templates/CISBaselines') -Filter '*.json' -File -Recurse
    $script:WinGetRoot = Join-Path $modulePath 'Templates/MobileApps/Windows/WinGet'
    $script:WinGetAppTemplates = Get-ChildItem -Path (Join-Path $script:WinGetRoot 'Apps') -Filter '*.json' -File
    $script:WinGetPresetTemplates = Get-ChildItem -Path (Join-Path $script:WinGetRoot 'Presets') -Filter '*.json' -File
    $script:WinGetSchemaTemplates = Get-ChildItem -Path (Join-Path $script:WinGetRoot 'Schemas') -Filter '*.json' -File
}

AfterAll {
    Remove-Module IntuneHydrationKit -Force -ErrorAction SilentlyContinue
}

Describe 'Bundled template contracts' {
    It 'Should load bundled OpenIntune and CIS templates as valid JSON' {
        $allTemplates = @($script:OpenIntuneTemplates) + @($script:CisTemplates)
        $allTemplates.Count | Should -BeGreaterThan 0

        foreach ($templateFile in $allTemplates) {
            {
                $null = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 100
            } | Should -Not -Throw
        }
    }

    It 'Should keep OpenIntune IntuneManagement and AppProtection templates routable by shared metadata' {
        $openIntuneTemplates = $script:OpenIntuneTemplates

        & $script:HydrationModule {
            param($TemplateFiles)

            $metadata = Get-BaselineImportMetadata -Kind 'OpenIntune'
            $templateFiles = $TemplateFiles | Where-Object {
                $normalizedDirectory = $_.DirectoryName -replace '\\', '/'
                $normalizedDirectory -match '/(IntuneManagement|AppProtection)(/|$)' -and
                $normalizedDirectory -notmatch '/NativeImport(/|$)'
            }

            $templateFiles.Count | Should -BeGreaterThan 0

            foreach ($templateFile in $templateFiles) {
                $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 100
                $metadata.ODataTypeToEndpoint.ContainsKey($template.'@odata.type') | Should -BeTrue -Because $templateFile.FullName
            }
        } $openIntuneTemplates
    }

    It 'Should keep CIS templates routable by shared metadata or importer fallback rules' {
        $cisTemplates = $script:CisTemplates

        & $script:HydrationModule {
            param($TemplateFiles)

            $metadata = Get-BaselineImportMetadata -Kind 'CIS'

            foreach ($templateFile in $TemplateFiles) {
                $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 100
                $endpoint = $null

                if ($template.'@odata.type' -and $metadata.ODataTypeToEndpoint.ContainsKey($template.'@odata.type')) {
                    $endpoint = $metadata.ODataTypeToEndpoint[$template.'@odata.type']
                } elseif ($template.'@odata.context') {
                    foreach ($contextFragment in $metadata.ODataContextToEndpoint.Keys) {
                        if ($template.'@odata.context' -like "*$contextFragment*") {
                            $endpoint = $metadata.ODataContextToEndpoint[$contextFragment]
                            break
                        }
                    }
                } elseif ($template.PSObject.Properties['settings'] -and $template.PSObject.Properties['platforms'] -and $template.PSObject.Properties['technologies']) {
                    $endpoint = 'deviceManagement/configurationPolicies'
                }

                $endpoint | Should -Not -BeNullOrEmpty -Because $templateFile.FullName
            }
        } $cisTemplates
    }

    It 'Should sanitize real templates that include invalid Graph navigation metadata' {
        $vsCodeTemplates = Get-ChildItem -Path (Join-Path $modulePath 'Templates/CISBaselines/4.0 - CIS Benchmarks/CIS - Visual Studio Code') -Filter '*.json' -File
        $templateFiles = @(
            $vsCodeTemplates
            (Get-Item -Path (Join-Path $modulePath 'Templates/OpenIntuneBaseline/WINDOWS/IntuneManagement/SettingsCatalog/Win - OIB - ES - Encryption - D - BitLocker (OS Disk) - v3.7.json'))
            (Get-Item -Path (Join-Path $modulePath 'Templates/OpenIntuneBaseline/WINDOWS/IntuneManagement/UpdatePolicies/Win - OIB - WUfB - Ring 1 - Pilot - v3.0.json'))
            (Get-Item -Path (Join-Path $modulePath 'Templates/CISBaselines/8.0 - Windows 11 Benchmarks/Intune Modern Workplace Windows 11/Baseline - Configure Outlook profile .json'))
        )

        & $script:HydrationModule {
            param($TemplateFiles)

            function Test-ContainsInvalidGraphMetadata {
                param(
                    [object]$Node
                )

                if ($null -eq $Node -or $Node -is [string]) {
                    return $false
                }

                if ($Node -is [System.Collections.IDictionary]) {
                    foreach ($dictionaryKey in $Node.Keys) {
                        if ($dictionaryKey -match '@odata\.(associationLink|navigationLink)' -or $dictionaryKey -eq 'settingDefinitions') {
                            return $true
                        }

                        if (Test-ContainsInvalidGraphMetadata -Node $Node[$dictionaryKey]) {
                            return $true
                        }
                    }

                    return $false
                }

                if ($Node -is [System.Collections.IEnumerable]) {
                    foreach ($item in $Node) {
                        if (Test-ContainsInvalidGraphMetadata -Node $item) {
                            return $true
                        }
                    }
                }

                if ($Node.PSObject -and $Node.PSObject.Properties) {
                    foreach ($property in $Node.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' }) {
                        if ($property.Name -match '@odata\.(associationLink|navigationLink)' -or $property.Name -eq 'settingDefinitions') {
                            return $true
                        }

                        if (Test-ContainsInvalidGraphMetadata -Node $property.Value) {
                            return $true
                        }
                    }
                }

                return $false
            }

            foreach ($templateFile in $TemplateFiles) {
                $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 100
                Test-ContainsInvalidGraphMetadata -Node $template | Should -BeTrue -Because $templateFile.FullName

                $cleanTemplate = Copy-DeepObject -InputObject $template

                Remove-ReadOnlyGraphProperties -InputObject $cleanTemplate -AdditionalProperties @(
                    'supportsScopeTags',
                    'deviceManagementApplicabilityRuleOsEdition',
                    'deviceManagementApplicabilityRuleOsVersion',
                    'deviceManagementApplicabilityRuleDeviceMode',
                    '@odata.id',
                    '@odata.editLink',
                    'creationSource',
                    'settingCount',
                    'priorityMetaData',
                    'assignments',
                    'settingDefinitions',
                    'isAssigned'
                )

                Test-ContainsInvalidGraphMetadata -Node $cleanTemplate | Should -BeFalse -Because $templateFile.FullName
            }
        } $templateFiles
    }

    It 'Should keep bundled WinGet app templates internally consistent' {
        $script:WinGetAppTemplates.Count | Should -Be 28

        $templateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($templateFile in $script:WinGetAppTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 100

            $template.'$schema' | Should -Be '../Schemas/winGetAppTemplate.schema.json' -Because $templateFile.FullName
            $template.schemaVersion | Should -Be '1.0.0' -Because $templateFile.FullName
            $template.templateId | Should -Match '^[a-z0-9]+(?:-[a-z0-9]+)*$' -Because $templateFile.FullName
            $template.packageIdentifier | Should -Not -BeNullOrEmpty -Because $templateFile.FullName
            $template.package.match.packageIdentifier | Should -Be $template.packageIdentifier -Because $templateFile.FullName
            $template.resolvedPackage.selectedInstaller | Should -Not -BeNullOrEmpty -Because $templateFile.FullName
            $template.resolvedPackage.manifestSource.repository | Should -Be 'microsoft/winget-pkgs' -Because $templateFile.FullName
            $template.icon.sourceType | Should -Be 'file' -Because $templateFile.FullName

            $templateIds.Add([string]$template.templateId) | Should -BeTrue -Because "Template IDs must be unique: $($template.templateId)"

            $iconPath = Join-Path -Path $templateFile.DirectoryName -ChildPath $template.icon.fileName
            Test-Path -Path $iconPath -PathType Leaf | Should -BeTrue -Because $templateFile.FullName

            $iconBytes = [System.IO.File]::ReadAllBytes($iconPath)
            $iconBytes[0..7] | Should -Be @(137, 80, 78, 71, 13, 10, 26, 10) -Because $templateFile.FullName
        }
    }

    It 'Should keep bundled WinGet presets aligned to existing app templates' {
        $script:WinGetPresetTemplates.Count | Should -BeGreaterThan 0
        $templateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($templateFile in $script:WinGetAppTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 100
            $null = $templateIds.Add([string]$template.templateId)
        }

        foreach ($presetFile in $script:WinGetPresetTemplates) {
            $preset = Get-Content -Path $presetFile.FullName -Raw | ConvertFrom-Json -Depth 100

            $preset.'$schema' | Should -Be '../Schemas/winGetAppPreset.schema.json' -Because $presetFile.FullName
            $preset.schemaVersion | Should -Be '1.0.0' -Because $presetFile.FullName
            $preset.appIds.Count | Should -BeGreaterThan 0 -Because $presetFile.FullName

            foreach ($appId in $preset.appIds) {
                $templateIds.Contains([string]$appId) | Should -BeTrue -Because "$presetFile references $appId"
            }
        }
    }

    It 'Should keep bundled WinGet schemas as valid JSON' {
        $script:WinGetSchemaTemplates.Count | Should -Be 2

        foreach ($schemaFile in $script:WinGetSchemaTemplates) {
            {
                $null = Get-Content -Path $schemaFile.FullName -Raw | ConvertFrom-Json -Depth 100
            } | Should -Not -Throw
        }
    }
}
