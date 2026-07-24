#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
    $script:HydrationModule = Get-Module IntuneHydrationKit

    $script:OpenIntuneTemplates = Get-ChildItem -Path (Join-Path $modulePath 'Templates/OpenIntuneBaseline') -Filter '*.json' -File -Recurse
    $script:CisTemplates = Get-ChildItem -Path (Join-Path $modulePath 'Templates/CISBaselines') -Filter '*.json' -File -Recurse
    $script:DynamicGroupTemplatePath = Join-Path $modulePath 'Templates/DynamicGroups'
    $script:DynamicGroupTemplates = Get-ChildItem -Path $script:DynamicGroupTemplatePath -Filter '*.json' -File
    $script:DeviceFilterTemplatePath = Join-Path $modulePath 'Templates/Filters'
    $script:DeviceFilterTemplates = Get-ChildItem -Path $script:DeviceFilterTemplatePath -Filter '*.json' -File
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

    It 'Should keep manifest release notes scoped to release notes only' {
        $manifest = Import-PowerShellDataFile -Path (Join-Path $modulePath 'IntuneHydrationKit.psd1')
        $releaseNotes = [string]$manifest.PrivateData.PSData.ReleaseNotes

        $releaseNotes | Should -Match '## v\d+\.\d+\.\d+'
        $releaseNotes | Should -Not -Match 'Install-Module'
        $releaseNotes | Should -Not -Match 'Update-Module'
        $releaseNotes | Should -Not -Match 'Install directly from the PowerShell Gallery'
    }

    It 'Should load bundled dynamic group templates as valid JSON with unique names' {
        $script:DynamicGroupTemplates.Count | Should -BeGreaterThan 0
        $displayNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($templateFile in $script:DynamicGroupTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 20
            $groups = @($template.groups)
            $groups.Count | Should -BeGreaterThan 0 -Because $templateFile.FullName

            foreach ($group in $groups) {
                [string]::IsNullOrWhiteSpace([string]$group.displayName) | Should -BeFalse -Because $templateFile.FullName
                [string]::IsNullOrWhiteSpace([string]$group.description) | Should -BeFalse -Because $templateFile.FullName
                [string]::IsNullOrWhiteSpace([string]$group.membershipRule) | Should -BeFalse -Because $templateFile.FullName

                if ($group.PSObject.Properties['platform']) {
                    [string]$group.platform | Should -BeIn @('All', 'Windows', 'macOS', 'iOS', 'Android') -Because $group.displayName
                }

                $displayNames.Add([string]$group.displayName) | Should -BeTrue -Because "Duplicate dynamic group name: $($group.displayName)"
            }
        }
    }

    It 'Should load bundled device filter templates as valid JSON with unique names' {
        $script:DeviceFilterTemplates.Count | Should -BeGreaterThan 0
        $displayNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($templateFile in $script:DeviceFilterTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 20
            $filters = @($template.filters)
            $filters.Count | Should -BeGreaterThan 0 -Because $templateFile.FullName

            foreach ($filter in $filters) {
                [string]::IsNullOrWhiteSpace([string]$filter.displayName) | Should -BeFalse -Because $templateFile.FullName
                [string]::IsNullOrWhiteSpace([string]$filter.description) | Should -BeFalse -Because $templateFile.FullName
                [string]::IsNullOrWhiteSpace([string]$filter.platform) | Should -BeFalse -Because $templateFile.FullName
                [string]::IsNullOrWhiteSpace([string]$filter.rule) | Should -BeFalse -Because $templateFile.FullName
                [string]$filter.platform | Should -BeIn @('androidForWork', 'iOS', 'macOS', 'windows10AndLater') -Because $filter.displayName

                $displayNames.Add([string]$filter.displayName) | Should -BeTrue -Because "Duplicate device filter name: $($filter.displayName)"
            }
        }
    }

    It 'Should include the web-app OS-version dynamic group templates' {
        $groups = foreach ($templateFile in $script:DynamicGroupTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 20
            @($template.groups)
        }
        $expectedGroups = @{
            'Intune - Windows 11 24H2 Devices'   = @{ Platform = 'Windows'; Rule = '(device.deviceOSType -eq "Windows") and (device.deviceOSVersion -startsWith "10.0.26100") and (device.managementType -eq "MDM")' }
            'Intune - Windows 11 25H2 Devices'   = @{ Platform = 'Windows'; Rule = '(device.deviceOSType -eq "Windows") and (device.deviceOSVersion -startsWith "10.0.26200") and (device.managementType -eq "MDM")' }
            'Intune - Windows 11 26H1 Devices'   = @{ Platform = 'Windows'; Rule = '(device.deviceOSType -eq "Windows") and (device.deviceOSVersion -startsWith "10.0.28000") and (device.managementType -eq "MDM")' }
            'Intune - macOS 27 Golden Gate Devices' = @{ Platform = 'macOS'; Rule = '(device.deviceOSType -eq "MacMDM") and (device.deviceOSVersion -startsWith "27.")' }
            'Intune - macOS 26 Tahoe Devices'    = @{ Platform = 'macOS'; Rule = '(device.deviceOSType -eq "MacMDM") and (device.deviceOSVersion -startsWith "26.")' }
            'Intune - macOS 15 Sequoia Devices'  = @{ Platform = 'macOS'; Rule = '(device.deviceOSType -eq "MacMDM") and (device.deviceOSVersion -startsWith "15.")' }
            'Intune - macOS 14 Sonoma Devices'   = @{ Platform = 'macOS'; Rule = '(device.deviceOSType -eq "MacMDM") and (device.deviceOSVersion -startsWith "14.")' }
            'Intune - iOS iPadOS 26 Devices'     = @{ Platform = 'iOS'; Rule = '((device.deviceOSType -eq "iOS") or (device.deviceOSType -eq "iPad")) and (device.deviceOSVersion -startsWith "26.")' }
            'Intune - iOS iPadOS 18 Devices'     = @{ Platform = 'iOS'; Rule = '((device.deviceOSType -eq "iOS") or (device.deviceOSType -eq "iPad")) and (device.deviceOSVersion -startsWith "18.")' }
        }

        $groups | Should -HaveCount 62
        foreach ($name in $expectedGroups.Keys) {
            $group = $groups | Where-Object { $_.displayName -eq $name }
            $group | Should -HaveCount 1
            $group.platform | Should -Be $expectedGroups[$name].Platform
            $group.membershipRule | Should -Be $expectedGroups[$name].Rule
        }
    }

    It 'Should include the web-app OS-version device filter templates' {
        $filters = foreach ($templateFile in $script:DeviceFilterTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 20
            @($template.filters)
        }
        $expectedFilters = @{
            'Windows - Windows 11 24H2 Devices'    = @{ Platform = 'windows10AndLater'; Rule = '(device.osVersion -startsWith "10.0.26100")' }
            'Windows - Windows 11 25H2 Devices'    = @{ Platform = 'windows10AndLater'; Rule = '(device.osVersion -startsWith "10.0.26200")' }
            'Windows - Windows 11 26H1 Devices'    = @{ Platform = 'windows10AndLater'; Rule = '(device.osVersion -startsWith "10.0.28000")' }
            'iOS - iOS 26 Devices'                 = @{ Platform = 'iOS'; Rule = '(device.osVersion -startsWith "26.")' }
            'iOS - iOS 18 Devices'                 = @{ Platform = 'iOS'; Rule = '(device.osVersion -startsWith "18.")' }
            'macOS - macOS 27 Golden Gate Devices' = @{ Platform = 'macOS'; Rule = '(device.osVersion -startsWith "27.")' }
            'macOS - macOS 26 Tahoe Devices'       = @{ Platform = 'macOS'; Rule = '(device.osVersion -startsWith "26.")' }
            'macOS - macOS 15 Sequoia Devices'     = @{ Platform = 'macOS'; Rule = '(device.osVersion -startsWith "15.")' }
            'macOS - macOS 14 Sonoma Devices'      = @{ Platform = 'macOS'; Rule = '(device.osVersion -startsWith "14.")' }
        }

        $filters | Should -HaveCount 42
        foreach ($name in $expectedFilters.Keys) {
            $filter = $filters | Where-Object { $_.displayName -eq $name }
            $filter | Should -HaveCount 1
            $filter.platform | Should -Be $expectedFilters[$name].Platform
            $filter.rule | Should -Be $expectedFilters[$name].Rule
        }
    }

    It 'Should keep architecture device filters on documented cpu architecture rules' {
        $architectureTemplateFiles = @(
            Join-Path $script:DeviceFilterTemplatePath 'Windows-Architecture-Filters.json'
            Join-Path $script:DeviceFilterTemplatePath 'macOS-Architecture-Filters.json'
        )
        $filters = foreach ($templateFile in $architectureTemplateFiles) {
            $template = Get-Content -Path $templateFile -Raw | ConvertFrom-Json -Depth 20
            @($template.filters)
        }
        $expectedFilters = @{
            'Windows - x64 Devices'           = @{ Platform = 'windows10AndLater'; Rule = '(device.cpuArchitecture -eq "amd64")' }
            'Windows - ARM64 Devices'         = @{ Platform = 'windows10AndLater'; Rule = '(device.cpuArchitecture -eq "arm64")' }
            'Windows - x86 Devices'           = @{ Platform = 'windows10AndLater'; Rule = '(device.cpuArchitecture -eq "x86")' }
            'macOS - Apple Silicon Devices'   = @{ Platform = 'macOS'; Rule = '(device.cpuArchitecture -eq "arm64")' }
            'macOS - Intel Devices'           = @{ Platform = 'macOS'; Rule = '(device.cpuArchitecture -eq "x64")' }
        }

        $filters | Should -HaveCount $expectedFilters.Count
        foreach ($filter in $filters) {
            $expectedFilters.ContainsKey([string]$filter.displayName) | Should -BeTrue -Because $filter.displayName
            $expected = $expectedFilters[[string]$filter.displayName]

            $filter.platform | Should -Be $expected.Platform
            $filter.rule | Should -Be $expected.Rule
        }
    }

    It 'Should include device trust type templates with service-specific values' {
        $groups = foreach ($templateFile in $script:DynamicGroupTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 20
            @($template.groups)
        }
        $filters = foreach ($templateFile in $script:DeviceFilterTemplates) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 20
            @($template.filters)
        }
        $expectedGroups = @{
            'Intune - Entra Joined Devices'        = @{ Platform = 'Windows'; Rule = '(device.deviceTrustType -eq "AzureAD")' }
            'Intune - Hybrid Entra Joined Devices' = @{ Platform = 'Windows'; Rule = '(device.deviceTrustType -eq "ServerAD")' }
            'Intune - Entra Registered Devices'    = @{ Platform = 'Windows'; Rule = '(device.deviceTrustType -eq "Workplace")' }
        }
        $expectedFilters = @{
            'Windows - Entra Joined'           = @{ Platform = 'windows10AndLater'; Rule = '(device.deviceTrustType -eq "Azure AD joined")' }
            'Windows - Hybrid Entra Joined'    = @{ Platform = 'windows10AndLater'; Rule = '(device.deviceTrustType -eq "Hybrid Azure AD joined")' }
            'Windows - Entra Registered'       = @{ Platform = 'windows10AndLater'; Rule = '(device.deviceTrustType -eq "Azure AD registered")' }
            'Windows - Unknown Entra Join Type' = @{ Platform = 'windows10AndLater'; Rule = '(device.deviceTrustType -eq "Unknown")' }
        }

        foreach ($name in $expectedGroups.Keys) {
            $group = $groups | Where-Object { $_.displayName -eq $name }
            $group | Should -HaveCount 1
            $group.platform | Should -Be $expectedGroups[$name].Platform
            $group.membershipRule | Should -Be $expectedGroups[$name].Rule
        }

        foreach ($name in $expectedFilters.Keys) {
            $filter = $filters | Where-Object { $_.displayName -eq $name }
            $filter | Should -HaveCount 1
            $filter.platform | Should -Be $expectedFilters[$name].Platform
            $filter.rule | Should -Be $expectedFilters[$name].Rule
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
            $template.install.command | Should -Match '(^|\s)--silent(\s|$)' -Because $templateFile.FullName
            $template.resolvedPackage.selectedInstaller.Scope | Should -Be $template.package.match.scope -Because $templateFile.FullName
            if ([string]$template.package.match.scope -eq 'user') {
                $template.install.experience | Should -Be 'user' -Because $templateFile.FullName
                $template.install.command | Should -Match '(^|\s)--scope user(\s|$)' -Because $templateFile.FullName
                $template.uninstall.command | Should -Match '(^|\s)--scope user(\s|$)' -Because $templateFile.FullName
            } else {
                $template.install.experience | Should -Be 'system' -Because $templateFile.FullName
                $template.install.command | Should -Match '(^|\s)--scope machine(\s|$)' -Because $templateFile.FullName
                $template.uninstall.command | Should -Match '(^|\s)--scope machine(\s|$)' -Because $templateFile.FullName
            }
            $template.resolvedPackage.selectedInstaller | Should -Not -BeNullOrEmpty -Because $templateFile.FullName
            $template.resolvedPackage.manifestSource.repository | Should -Be 'microsoft/winget-pkgs' -Because $templateFile.FullName
            $template.icon.sourceType | Should -Be 'file' -Because $templateFile.FullName
            if ($null -ne $template.resolvedPackage.selectedInstaller.InstallerLocale) {
                [string]::IsNullOrWhiteSpace($template.resolvedPackage.selectedInstaller.InstallerLocale) | Should -BeFalse -Because $templateFile.FullName
            }

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
            $preset.selectionCriteria.candidateSource.Contains('Winget') | Should -BeFalse -Because $presetFile.FullName
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

    It 'Should require runtime-critical fields in the WinGet app schema' {
        $schemaFile = Join-Path $script:WinGetRoot 'Schemas/winGetAppTemplate.schema.json'
        $schema = Get-Content -Path $schemaFile -Raw | ConvertFrom-Json -Depth 100

        $schema.required | Should -Contain 'resolvedPackage'

        $fileIconRule = $schema.properties.icon.allOf | Where-Object {
            $_.if.properties.sourceType.const -eq 'file'
        } | Select-Object -First 1

        $fileIconRule | Should -Not -BeNullOrEmpty
        $fileIconRule.then.required | Should -Contain 'fileName'
        $fileIconRule.then.properties.fileName.type | Should -Be 'string'
        $fileIconRule.then.properties.fileName.minLength | Should -Be 1
    }
}
