#Requires -Modules Pester

BeforeAll {
    $script:batchOperationItems = @()
    $script:invokeTemplateCallCount = 0
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    $script:ModuleManifestPath = Join-Path $modulePath 'IntuneHydrationKit.psd1'
    Get-Module -Name IntuneHydrationKit -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:ModuleManifestPath -Force
    $script:TestModule = Get-Module -Name IntuneHydrationKit | Select-Object -First 1

    if (-not $script:TestModule) {
        throw 'Failed to import IntuneHydrationKit module'
    }

    function New-TestResolvedWinGetPackage {
        param(
            [Parameter(Mandatory)]
            [string]$PackageIdentifier,

            [Parameter(Mandatory)]
            [string]$PackageVersion,

            [Parameter(Mandatory)]
            [string]$InstallerUrl,

            [Parameter()]
            [string]$InstallerType = 'exe'
        )

        [pscustomobject]@{
            packageVersion    = $PackageVersion
            manifestSource    = [pscustomobject]@{
                repository  = 'microsoft/winget-pkgs'
                ref         = 'master'
                packagePath = "manifests/test/$PackageIdentifier"
                versionPath = "manifests/test/$PackageIdentifier/$PackageVersion"
            }
            selectedInstaller = [pscustomobject]@{
                Architecture  = 'x64'
                Scope         = 'machine'
                InstallerType = $InstallerType
                InstallerUrl  = $InstallerUrl
            }
        }
    }

    function New-TestExistingWinGetApp {
        param(
            [Parameter()]
            [string]$Id = 'existing-id',

            [Parameter()]
            [string]$DisplayName = 'Contoso App - [IHD]',

            [Parameter()]
            [string]$PackageIdentifier = 'Contoso.App'
        )

        @{
            id          = $Id
            displayName = $DisplayName
            description = 'WinGet packaged Contoso app - Imported by Intune Hydration Kit'
            notes       = "Imported from WinGet`nWinGetPackageIdentifier: $PackageIdentifier"
        }
    }

    function Set-TestExistingWinGetAppsMock {
        param(
            [Parameter(Mandatory)]
            [object[]]$Apps
        )

        $script:testExistingWinGetApps = @($Apps)
        Mock Invoke-HydrationGraphRequest {
            param($Method)
            if ($Method -eq 'GET') {
                return @{
                    value             = @($script:testExistingWinGetApps)
                    '@odata.nextLink' = $null
                }
            }
        } -ModuleName IntuneHydrationKit
    }
}

Describe 'Import-IntuneWinGetApp' {
    BeforeEach {
        Get-Module -Name IntuneHydrationKit -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $script:ModuleManifestPath -Force
        $script:TestModule = Get-Module -Name IntuneHydrationKit | Select-Object -First 1

        $script:workingRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/Import-IntuneWinGetApp'
        $script:generatedScriptsRoot = Join-Path $script:workingRoot 'generated-scripts'
        if (Test-Path -Path $script:workingRoot) {
            Remove-Item -Path $script:workingRoot -Recurse -Force
        }

        $null = New-Item -Path $script:workingRoot -ItemType Directory -Force
        & $script:TestModule {
            param($GeneratedScriptsPath)
            $script:GeneratedScriptsPath = $GeneratedScriptsPath
            $script:GeneratedScriptsNoticeWritten = $false
            $script:HydrationSessionId = 'test-session'
        } $script:generatedScriptsRoot
        $script:deletedGraphUris = @()
        Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        Mock Publish-IntuneWin32AppContent {
            param($AppId)

            [pscustomobject]@{
                AppId = $AppId
            }
        } -ModuleName IntuneHydrationKit
        Mock Get-HydrationWinGetAppTemplates {
            @(
                [pscustomobject]@{
                    templateId        = 'contoso-app'
                    packageIdentifier = 'Contoso.App'
                    displayName       = 'Contoso App'
                    publisher         = 'Contoso Template Publisher'
                    description       = 'WinGet packaged Contoso app'
                    TemplatePath      = 'Templates/MobileApps/Windows/WinGet/Apps/contoso-app.json'
                    resolvedPackage  = New-TestResolvedWinGetPackage -PackageIdentifier 'Contoso.App' -PackageVersion '2.0.0' -InstallerUrl 'https://downloads.contoso.test/app.exe'
                    package           = [pscustomobject]@{
                        match = [pscustomobject]@{
                            architectures = @('x64')
                            scope         = 'machine'
                            locale        = 'en-US'
                        }
                    }
                    install           = [pscustomobject]@{
                        command         = 'winget install --id Contoso.App --exact --silent --scope machine --accept-package-agreements --accept-source-agreements'
                        experience      = 'system'
                        restartBehavior = 'suppress'
                    }
                    uninstall         = [pscustomobject]@{
                        command  = 'winget uninstall --id Contoso.App --exact --silent'
                        behavior = 'allow'
                    }
                    detection         = [pscustomobject]@{
                        strategy = 'generated'
                    }
                    requirements      = [pscustomobject]@{
                        minimumSupportedWindowsRelease = 'W10_22H2'
                        architectures                  = @('x64')
                        minimumFreeDiskSpaceInMB       = 1024
                        minimumMemoryInMB              = 2048
                    }
                    icon              = [pscustomobject]@{
                        sourceType = 'none'
                        fileName   = $null
                    }
                    metadata          = [pscustomobject]@{
                        notes        = @('Template note')
                        placeholders = [pscustomobject]@{
                            customNotes = @('Tenant note')
                            owner       = 'Endpoint Engineering'
                            scopeTagIds = @('1', '2')
                        }
                        markers      = [pscustomobject]@{
                            hydration = 'Imported by Intune Hydration Kit'
                            source    = 'Imported from WinGet'
                        }
                    }
                }
            )
        } -ModuleName IntuneHydrationKit
        Mock Invoke-HydrationGraphRequest {
            param($Method, $Uri, $Body)
            $null = $Uri
            switch ($Method) {
                'GET' {
                    return @{ value = @(); '@odata.nextLink' = $null }
                }
                'POST' {
                    $script:capturedCreateBody = $Body
                    return @{ id = 'app-123' }
                }
                'DELETE' {
                    return @{}
                }
            }
        } -ModuleName IntuneHydrationKit
        Mock Invoke-GraphBatchOperation { @() } -ModuleName IntuneHydrationKit
        Mock Sync-IntuneWinGetProactiveRemediation { @() } -ModuleName IntuneHydrationKit
    }

    AfterEach {
        if (Test-Path -Path $script:workingRoot) {
            Remove-Item -Path $script:workingRoot -Recurse -Force
        }
        & $script:TestModule {
            $script:GeneratedScriptsPath = $null
            $script:GeneratedScriptsNoticeWritten = $false
            $script:HydrationSessionId = $null
        }
        $script:capturedCreateBody = $null
        $script:deletedGraphUris = @()
        $script:batchOperationItems = @()
        $script:invokeTemplateCallCount = 0
        $script:testExistingWinGetApps = @()
    }

    It 'Should create a WinGet-backed Win32 app with ownership metadata' {
        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Created'
        $result[0].Name | Should -Be 'Contoso App - [IHD]'
        $script:capturedCreateBody.displayName | Should -Be 'Contoso App - [IHD]'
        $script:capturedCreateBody.description | Should -BeLike '*Imported by Intune Hydration Kit*'
        $script:capturedCreateBody.publisher | Should -Be 'Contoso Template Publisher'
        $script:capturedCreateBody.developer | Should -Be 'Contoso Template Publisher'
        $script:capturedCreateBody.notes | Should -BeLike '*Imported from WinGet*'
        $script:capturedCreateBody.notes | Should -BeLike '*WinGetPackageIdentifier: Contoso.App*'
        $script:capturedCreateBody.appVersion | Should -Be '2.0.0'
        $script:capturedCreateBody.installCommandLine | Should -Be 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Install-WinGetPackage.ps1'
        $script:capturedCreateBody.uninstallCommandLine | Should -Be 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Uninstall-WinGetPackage.ps1'
        $script:capturedCreateBody.allowAvailableUninstall | Should -BeTrue
        $script:capturedCreateBody.applicableArchitectures | Should -Be 'x64'
        $script:capturedCreateBody.minimumFreeDiskSpaceInMB | Should -Be 1024
        $script:capturedCreateBody.minimumMemoryInMB | Should -Be 2048
        $script:capturedCreateBody.roleScopeTagIds | Should -Be @('1', '2')
        $script:capturedCreateBody.rules | Should -HaveCount 1
        $rule = @($script:capturedCreateBody.rules) | Select-Object -First 1
        $scriptRuleType = if ($rule -is [hashtable]) { $rule['@odata.type'] } else { $rule.'@odata.type' }
        $scriptRuleContent = if ($rule -is [hashtable]) { $rule['scriptContent'] } else { $rule.scriptContent }
        $scriptRuleType | Should -Be '#microsoft.graph.win32LobAppPowerShellScriptRule'
        $decodedScript = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($scriptRuleContent))
        $decodedScript | Should -Match "\$PackageIdentifier = 'Contoso\.App'"
        $decodedScript | Should -Match "\$PackageIdentifierPattern = 'Contoso\\\.App'"
        $decodedScript | Should -Match 'Install-WinGetSystemBootstrap'
        $decodedScript | Should -Match 'winget list --id "\$PackageIdentifier" --exact --accept-source-agreements'
        $decodedScript | Should -Not -Match '--source winget'
        $decodedScript | Should -Match 'Test-InstalledApplicationRegistry'
        Should -Invoke Publish-IntuneWin32AppContent -Exactly 1 -ModuleName IntuneHydrationKit
    }

    It 'Should include a large icon when one is resolved for the template' {
        Mock Resolve-WinGetAppIcon {
            [pscustomobject]@{
                Base64   = 'ZmFrZS1pY29u'
                MimeType = 'image/png'
                Source   = 'https://icons.contoso.test/contoso.png'
            }
        } -ModuleName IntuneHydrationKit

        $null = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $script:capturedCreateBody.largeIcon.value | Should -Be 'ZmFrZS1pY29u'
        $script:capturedCreateBody.largeIcon.type | Should -Be 'image/png'
    }

    It 'Should generate shared WinGet detection rules and multi-architecture requirements' {
        $templateRoot = Join-Path $script:workingRoot 'template'
        $null = New-Item -Path $templateRoot -ItemType Directory -Force
        $script:everythingTemplatePath = Join-Path $templateRoot 'everything-search.json'
        '{}' | Set-Content -Path $script:everythingTemplatePath -Encoding utf8

        Mock Get-HydrationWinGetAppTemplates {
            @(
                [pscustomobject]@{
                    templateId        = 'everything-search'
                    packageIdentifier = 'voidtools.Everything'
                    displayName       = 'Everything'
                    publisher         = 'voidtools'
                    description       = 'WinGet packaged Everything'
                    TemplatePath      = $script:everythingTemplatePath
                    resolvedPackage  = New-TestResolvedWinGetPackage -PackageIdentifier 'voidtools.Everything' -PackageVersion '1.4.1.1032' -InstallerUrl 'https://www.voidtools.com/Everything-1.4.1.1032.x64.msi' -InstallerType 'wix'
                    package           = [pscustomobject]@{
                        match = [pscustomobject]@{
                            architectures = @('x64', 'x86', 'arm64')
                            scope         = 'machine'
                            locale        = 'en-US'
                        }
                    }
                    install           = [pscustomobject]@{
                        command         = 'winget install --id voidtools.Everything --exact --silent --scope machine --accept-package-agreements --accept-source-agreements'
                        experience      = 'system'
                        restartBehavior = 'suppress'
                    }
                    uninstall         = [pscustomobject]@{
                        command  = 'winget uninstall --id voidtools.Everything --exact --silent'
                        behavior = 'allow'
                    }
                    detection         = [pscustomobject]@{
                        strategy = 'generated'
                    }
                    requirements      = [pscustomobject]@{
                        minimumSupportedWindowsRelease = 'W10_22H2'
                        architectures                  = @('x64', 'x86', 'arm64')
                        minimumFreeDiskSpaceInMB       = $null
                        minimumMemoryInMB              = $null
                    }
                    icon              = [pscustomobject]@{
                        sourceType = 'none'
                        fileName   = $null
                    }
                    metadata          = [pscustomobject]@{
                        notes        = @()
                        placeholders = [pscustomobject]@{
                            customNotes = @()
                            owner       = ''
                            scopeTagIds = @()
                        }
                        markers      = [pscustomobject]@{
                            hydration = 'Imported by Intune Hydration Kit'
                            source    = 'Imported from WinGet'
                        }
                    }
                }
            )
        } -ModuleName IntuneHydrationKit

        $null = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $script:capturedCreateBody.rules | Should -HaveCount 1
        $scriptRule = @($script:capturedCreateBody.rules) | Select-Object -First 1
        $scriptRuleType = if ($scriptRule -is [hashtable]) { $scriptRule['@odata.type'] } else { $scriptRule.'@odata.type' }
        $scriptRuleContent = if ($scriptRule -is [hashtable]) { $scriptRule['scriptContent'] } else { $scriptRule.scriptContent }
        $scriptRuleType | Should -Be '#microsoft.graph.win32LobAppPowerShellScriptRule'
        $decodedScript = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($scriptRuleContent))
        $decodedScript | Should -Match "\$PackageIdentifier = 'voidtools\.Everything'"
        $decodedScript | Should -Match "\$PackageIdentifierPattern = 'voidtools\\\.Everything'"
        $decodedScript | Should -Match 'Install-WinGetSystemBootstrap'
        $decodedScript | Should -Match 'winget list --id "\$PackageIdentifier" --exact --accept-source-agreements'
        $decodedScript | Should -Not -Match '--source winget'
        $decodedScript | Should -Match 'Test-InstalledApplicationRegistry'
        $script:capturedCreateBody.ContainsKey('applicableArchitectures') | Should -BeFalse
    }

    It 'Should sync proactive remediations when enabled' {
        $null = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -RemediationEnabled

        Should -Invoke Sync-IntuneWinGetProactiveRemediation -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
            @($Templates).Count -eq 1 -and
            $WhatIfEnabled -eq $false -and
            (-not $RemoveExisting)
        }
    }

    It 'Should keep generated script detection when the selected installer has a ProductCode' {
        Mock Publish-IntuneWin32AppContent {
            [PSCustomObject]@{
                AppId              = 'msi-app-id'
                ContentVersionId   = 'version-1'
                ContentFileId      = 'file-1'
                PackagePath        = 'C:\staging\7zip.7zip.intunewin'
                EncryptedSize      = 1024
                UnencryptedSize    = 2048
                UploadedChunkCount = 1
            }
        } -ModuleName IntuneHydrationKit

        $null = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $script:capturedCreateBody.rules | Should -HaveCount 1
        $scriptRule = @($script:capturedCreateBody.rules) | Select-Object -First 1
        $scriptRuleType = if ($scriptRule -is [hashtable]) { $scriptRule['@odata.type'] } else { $scriptRule.'@odata.type' }
        $scriptRuleContent = if ($scriptRule -is [hashtable]) { $scriptRule['scriptContent'] } else { $scriptRule.scriptContent }
        $scriptRuleType | Should -Be '#microsoft.graph.win32LobAppPowerShellScriptRule'
        $decodedScript = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($scriptRuleContent))
        $decodedScript | Should -Match "\$PackageIdentifier = 'Contoso\.App'"
        $decodedScript | Should -Not -Match ([regex]::Escape('{23170F69-40C1-2702-2490-000001000000}'))
    }

    It 'Should generate wrapper scripts that log to the IntuneManagementExtension log directory' {
        $script:capturedInstallScript = $null
        $script:capturedUninstallScript = $null
        $script:capturedDetectionScript = $null

        Mock New-IntuneWinPackage {
            [pscustomobject]@{
                OutputPath      = Join-Path $script:workingRoot 'contoso-app.intunewin'
                SetupFile       = 'Install-WinGetPackage.ps1'
                UnencryptedSize = 1234
            }
        } -ModuleName IntuneHydrationKit

        Mock New-IntuneWin32AppPayload {
            param($ScriptRootPath)

            $script:capturedInstallScript = Get-Content -Path (Join-Path $ScriptRootPath 'Install-WinGetPackage.ps1') -Raw
            $script:capturedUninstallScript = Get-Content -Path (Join-Path $ScriptRootPath 'Uninstall-WinGetPackage.ps1') -Raw
            $script:capturedDetectionScript = Get-Content -Path (Join-Path $ScriptRootPath 'Detect-WinGetPackage.ps1') -Raw

            @{
                displayName = 'Contoso App'
            }
        } -ModuleName IntuneHydrationKit

        $null = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($script:capturedInstallScript, [ref]$null, [ref]$parseErrors) | Out-Null
        $parseErrors | Should -BeNullOrEmpty
        [System.Management.Automation.Language.Parser]::ParseInput($script:capturedDetectionScript, [ref]$null, [ref]$parseErrors) | Out-Null
        $parseErrors | Should -BeNullOrEmpty
        [System.Management.Automation.Language.Parser]::ParseInput($script:capturedUninstallScript, [ref]$null, [ref]$parseErrors) | Out-Null
        $parseErrors | Should -BeNullOrEmpty
        $script:capturedInstallScript | Should -Match 'Microsoft\\IntuneManagementExtension\\Logs'
        $script:capturedInstallScript | Should -Match "\$operationName = 'Install'"
        $script:capturedInstallScript | Should -Match "\$packageIdentifier = 'Contoso.App'"
        $script:capturedInstallScript | Should -Match 'IntuneHydrationKit-WinGet-\$operationName-\$safePackageIdentifier\.log'
        $script:capturedInstallScript | Should -Match '\-1978335189'
        $script:capturedInstallScript | Should -Match 'Test-WinGetAlreadyInstalledNoUpgradeOutput'
        $script:capturedInstallScript | Should -Match 'Found an existing package already installed'
        $script:capturedInstallScript | Should -Match 'No available upgrade found'
        $script:capturedInstallScript | Should -Match 'No newer package versions are available'
        $script:capturedInstallScript | Should -Match "\$operationName -eq 'Install'"
        $script:capturedInstallScript | Should -Match 'Package already installed \(no upgrade needed\)'
        $script:capturedInstallScript | Should -Match 'RedirectStandardOutput'
        $script:capturedInstallScript | Should -Match 'RedirectStandardError'
        $script:capturedInstallScript | Should -Match 'Microsoft\.DesktopAppInstaller'
        $script:capturedInstallScript | Should -Match 'Install-WinGetSystemBootstrap'
        $script:capturedInstallScript | Should -Match 'NT AUTHORITY\\SYSTEM'
        $script:capturedUninstallScript | Should -Match "\$operationName = 'Uninstall'"
        $script:capturedUninstallScript | Should -Match "\$packageIdentifier = 'Contoso.App'"
        $script:capturedUninstallScript | Should -Match "\$operationName -eq 'Install'"
        $script:capturedDetectionScript | Should -Match "\$PackageIdentifier = 'Contoso\.App'"
        $script:capturedDetectionScript | Should -Match "\$PackageIdentifierPattern = 'Contoso\\\.App'"
        $script:capturedDetectionScript | Should -Match "\$DisplayName = 'Contoso App'"
        $script:capturedDetectionScript | Should -Match "\$Publisher = 'Contoso Template Publisher'"
        $script:capturedDetectionScript | Should -Match '--exact'
        $script:capturedDetectionScript | Should -Not -Match '--source winget'
        $script:capturedDetectionScript | Should -Match 'Test-InstalledApplicationRegistry'
        $script:capturedDetectionScript | Should -Match 'Install-WinGetSystemBootstrap'
        $script:capturedDetectionScript | Should -Match 'NT AUTHORITY\\SYSTEM'
        (Join-Path $script:generatedScriptsRoot 'WinGetApps/contoso-app/Install-WinGetPackage.ps1') | Should -Exist
        (Join-Path $script:generatedScriptsRoot 'WinGetApps/contoso-app/Uninstall-WinGetPackage.ps1') | Should -Exist
        (Join-Path $script:generatedScriptsRoot 'WinGetApps/contoso-app/Detection/Detect-WinGetPackage.ps1') | Should -Exist
    }

    It 'Should skip apps already owned by the WinGet hydration importer' {
        Set-TestExistingWinGetAppsMock -Apps @(New-TestExistingWinGetApp)

        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Skipped'
        $result[0].Name | Should -Be 'Contoso App - [IHD]'
        Should -Not -Invoke Publish-IntuneWin32AppContent -ModuleName IntuneHydrationKit
    }

    It 'Should skip WinGet-owned apps with a legacy prefixed name' {
        Set-TestExistingWinGetAppsMock -Apps @(New-TestExistingWinGetApp -DisplayName '[IHD] Contoso App')

        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Skipped'
        $result[0].Name | Should -Be 'Contoso App - [IHD]'
        $result[0].Id | Should -Be 'existing-id'
        Should -Not -Invoke Publish-IntuneWin32AppContent -ModuleName IntuneHydrationKit
    }

    It 'Should delete proactive remediations with app deletes when enabled' {
        Set-TestExistingWinGetAppsMock -Apps @(New-TestExistingWinGetApp)

        $null = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -RemoveExisting -RemediationEnabled

        Should -Invoke Sync-IntuneWinGetProactiveRemediation -ModuleName IntuneHydrationKit -Times 1 -ParameterFilter {
            $RemoveExisting -and
            $WhatIfEnabled -eq $false
        }
    }

    It 'Should only delete template-scoped WinGet-owned apps' {
        Set-TestExistingWinGetAppsMock -Apps @(
            New-TestExistingWinGetApp -Id 'delete-me'
            New-TestExistingWinGetApp -Id 'leave-me' -DisplayName 'Other App - [IHD]' -PackageIdentifier 'Other.App'
        )
        Mock Invoke-GraphBatchOperation {
            $script:batchOperationItems = @($Items)
            @(
                [pscustomobject]@{
                    Name   = 'Contoso App - [IHD]'
                    Type   = 'WinGetWin32App'
                    Action = 'Deleted'
                    Status = 'Success'
                    Id     = 'delete-me'
                }
            )
        } -ModuleName IntuneHydrationKit

        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -RemoveExisting

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Deleted'
        $script:batchOperationItems | Should -HaveCount 1
        $script:batchOperationItems[0].Id | Should -Be 'delete-me'
    }

    It 'Should delete WinGet-owned apps with a legacy prefixed name' {
        Set-TestExistingWinGetAppsMock -Apps @(New-TestExistingWinGetApp -Id 'delete-me' -DisplayName '[IHD] Contoso App')
        Mock Invoke-GraphBatchOperation {
            $script:batchOperationItems = @($Items)
            @(
                [pscustomobject]@{
                    Name   = '[IHD] Contoso App'
                    Type   = 'WinGetWin32App'
                    Action = 'Deleted'
                    Status = 'Success'
                    Id     = 'delete-me'
                }
            )
        } -ModuleName IntuneHydrationKit

        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -RemoveExisting

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Deleted'
        $result[0].Name | Should -Be '[IHD] Contoso App'
        $script:batchOperationItems | Should -HaveCount 1
        $script:batchOperationItems[0].Id | Should -Be 'delete-me'
    }

    It 'Should return dry-run delete results without calling the batch deleter' {
        Set-TestExistingWinGetAppsMock -Apps @(New-TestExistingWinGetApp -Id 'delete-me')

        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -RemoveExisting -WhatIf

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'WouldDelete'
        $result[0].Status | Should -Be 'DryRun'
        Should -Not -Invoke Invoke-GraphBatchOperation -ModuleName IntuneHydrationKit
    }

    It 'Should clean up the created app when content publishing fails' {
        Mock Publish-IntuneWin32AppContent {
            throw 'Upload failed'
        } -ModuleName IntuneHydrationKit
        Mock Invoke-HydrationGraphRequest {
            param($Method, $Uri, $Body)

            if ($Method -eq 'GET') {
                return @{ value = @(); '@odata.nextLink' = $null }
            }

            if ($Method -eq 'POST') {
                $script:capturedCreateBody = $Body
                return @{ id = 'app-123' }
            }

            if ($Method -eq 'DELETE') {
                $script:deletedGraphUris += $Uri
                return @{}
            }
        } -ModuleName IntuneHydrationKit

        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Failed'
        $result[0].Status | Should -BeLike '*Upload failed*'
        $script:deletedGraphUris | Should -Contain 'beta/deviceAppManagement/mobileApps/app-123'
        Should -Invoke Publish-IntuneWin32AppContent -Exactly 1 -ModuleName IntuneHydrationKit
    }

    It 'Should return dry-run results without packaging when WhatIf is used' {
        $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -WhatIf

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'WouldCreate'
        $result[0].Status | Should -Be 'DryRun'
        Should -Not -Invoke Publish-IntuneWin32AppContent -ModuleName IntuneHydrationKit
    }

    Context 'packageIdentifier validation' {
        It 'Should skip template with missing packageIdentifier and return Failed result' {
            Mock Get-HydrationWinGetAppTemplates {
                @(
                    [pscustomobject]@{
                        templateId   = 'bad-template'
                        displayName  = 'Bad App'
                        publisher    = 'Bad Publisher'
                        description  = 'Bad app description'
                        TemplatePath = 'Templates/MobileApps/Windows/WinGet/Apps/bad-template.json'
                        package      = [pscustomobject]@{
                            match = [pscustomobject]@{
                                architectures = @('x64')
                                scope         = 'machine'
                            }
                        }
                        install      = [pscustomobject]@{
                            command         = 'winget install --id Bad.App --exact --silent --scope machine'
                            experience      = 'system'
                            restartBehavior = 'suppress'
                        }
                        uninstall    = [pscustomobject]@{
                            command  = 'winget uninstall --id Bad.App --exact --silent'
                            behavior = 'allow'
                        }
                        detection    = [pscustomobject]@{
                            strategy = 'generated'
                        }
                        requirements = [pscustomobject]@{
                            minimumSupportedWindowsRelease = 'W10_22H2'
                            architectures                  = @('x64')
                        }
                        icon         = [pscustomobject]@{
                            sourceType = 'none'
                        }
                        metadata     = [pscustomobject]@{
                            notes        = @()
                            placeholders = [pscustomobject]@{
                                customNotes = @()
                                owner       = ''
                                scopeTagIds = @()
                            }
                            markers      = [pscustomobject]@{
                                hydration = 'Imported by Intune Hydration Kit'
                                source    = 'Imported from WinGet'
                            }
                        }
                    }
                )
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -TemplateId 'bad-template'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Missing or blank packageIdentifier*'
            Should -Not -Invoke Publish-IntuneWin32AppContent -ModuleName IntuneHydrationKit
        }

        It 'Should skip template with blank packageIdentifier and return Failed result' {
            Mock Get-HydrationWinGetAppTemplates {
                @(
                    [pscustomobject]@{
                        templateId        = 'blank-template'
                        packageIdentifier = ''
                        displayName       = 'Blank App'
                        publisher         = 'Blank Publisher'
                        description       = 'Blank app description'
                        TemplatePath      = 'Templates/MobileApps/Windows/WinGet/Apps/blank-template.json'
                        package           = [pscustomobject]@{
                            match = [pscustomobject]@{
                                architectures = @('x64')
                                scope         = 'machine'
                            }
                        }
                        install           = [pscustomobject]@{
                            command         = 'winget install --id Blank.App --exact --silent --scope machine'
                            experience      = 'system'
                            restartBehavior = 'suppress'
                        }
                        uninstall         = [pscustomobject]@{
                            command  = 'winget uninstall --id Blank.App --exact --silent'
                            behavior = 'allow'
                        }
                        detection         = [pscustomobject]@{
                            strategy = 'generated'
                        }
                        requirements      = [pscustomobject]@{
                            minimumSupportedWindowsRelease = 'W10_22H2'
                            architectures                  = @('x64')
                        }
                        icon              = [pscustomobject]@{
                            sourceType = 'none'
                        }
                        metadata          = [pscustomobject]@{
                            notes        = @()
                            placeholders = [pscustomobject]@{
                                customNotes = @()
                                owner       = ''
                                scopeTagIds = @()
                            }
                            markers      = [pscustomobject]@{
                                hydration = 'Imported by Intune Hydration Kit'
                                source    = 'Imported from WinGet'
                            }
                        }
                    }
                )
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -TemplateId 'blank-template'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Missing or blank packageIdentifier*'
            Should -Not -Invoke Publish-IntuneWin32AppContent -ModuleName IntuneHydrationKit
        }

        It 'Should skip template with whitespace-only packageIdentifier and return Failed result' {
            Mock Get-HydrationWinGetAppTemplates {
                @(
                    [pscustomobject]@{
                        templateId        = 'space-template'
                        packageIdentifier = '   '
                        displayName       = 'Space App'
                        publisher         = 'Space Publisher'
                        description       = 'Space app description'
                        TemplatePath      = 'Templates/MobileApps/Windows/WinGet/Apps/space-template.json'
                        package           = [pscustomobject]@{
                            match = [pscustomobject]@{
                                architectures = @('x64')
                                scope         = 'machine'
                            }
                        }
                        install           = [pscustomobject]@{
                            command         = 'winget install --id Space.App --exact --silent --scope machine'
                            experience      = 'system'
                            restartBehavior = 'suppress'
                        }
                        uninstall         = [pscustomobject]@{
                            command  = 'winget uninstall --id Space.App --exact --silent'
                            behavior = 'allow'
                        }
                        detection         = [pscustomobject]@{
                            strategy = 'generated'
                        }
                        requirements      = [pscustomobject]@{
                            minimumSupportedWindowsRelease = 'W10_22H2'
                            architectures                  = @('x64')
                        }
                        icon              = [pscustomobject]@{
                            sourceType = 'none'
                        }
                        metadata          = [pscustomobject]@{
                            notes        = @()
                            placeholders = [pscustomobject]@{
                                customNotes = @()
                                owner       = ''
                                scopeTagIds = @()
                            }
                            markers      = [pscustomobject]@{
                                hydration = 'Imported by Intune Hydration Kit'
                                source    = 'Imported from WinGet'
                            }
                        }
                    }
                )
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -TemplateId 'space-template'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Failed'
            $result[0].Status | Should -BeLike '*Missing or blank packageIdentifier*'
            Should -Not -Invoke Publish-IntuneWin32AppContent -ModuleName IntuneHydrationKit
        }

        It 'Should process template with valid packageIdentifier normally' {
            Mock Get-HydrationWinGetAppTemplates {
                @(
                    [pscustomobject]@{
                        templateId        = 'valid-template'
                        packageIdentifier = 'Valid.App'
                        displayName       = 'Valid App'
                        publisher         = 'Valid Publisher'
                        description       = 'Valid app description'
                        TemplatePath      = 'Templates/MobileApps/Windows/WinGet/Apps/valid-template.json'
                        resolvedPackage  = New-TestResolvedWinGetPackage -PackageIdentifier 'Valid.App' -PackageVersion '1.0.0' -InstallerUrl 'https://downloads.valid.test/app.exe'
                        package           = [pscustomobject]@{
                            match = [pscustomobject]@{
                                architectures = @('x64')
                                scope         = 'machine'
                                locale        = 'en-US'
                            }
                        }
                        install           = [pscustomobject]@{
                            command         = 'winget install --id Valid.App --exact --silent --scope machine --accept-package-agreements --accept-source-agreements'
                            experience      = 'system'
                            restartBehavior = 'suppress'
                        }
                        uninstall         = [pscustomobject]@{
                            command  = 'winget uninstall --id Valid.App --exact --silent'
                            behavior = 'allow'
                        }
                        detection         = [pscustomobject]@{
                            strategy = 'generated'
                        }
                        requirements      = [pscustomobject]@{
                            minimumSupportedWindowsRelease = 'W10_22H2'
                            architectures                  = @('x64')
                            minimumFreeDiskSpaceInMB       = 1024
                            minimumMemoryInMB              = 2048
                        }
                        icon              = [pscustomobject]@{
                            sourceType = 'none'
                            fileName   = $null
                        }
                        metadata          = [pscustomobject]@{
                            notes        = @('Template note')
                            placeholders = [pscustomobject]@{
                                customNotes = @('Tenant note')
                                owner       = 'Endpoint Engineering'
                                scopeTagIds = @('1', '2')
                            }
                            markers      = [pscustomobject]@{
                                hydration = 'Imported by Intune Hydration Kit'
                                source    = 'Imported from WinGet'
                            }
                        }
                    }
                )
            } -ModuleName IntuneHydrationKit
            Mock Invoke-IntuneWinGetAppTemplate {
                $script:invokeTemplateCallCount += 1
                [pscustomobject]@{
                    Name   = 'Valid App - [IHD]'
                    Id     = 'app-456'
                    Path   = 'Templates/MobileApps/Windows/WinGet/Apps/valid-template.json'
                    Type   = 'WinGetWin32App'
                    Action = 'Created'
                    Status = '1.0.0'
                }
            } -ModuleName IntuneHydrationKit

            $result = Import-IntuneWinGetApp -WorkingDirectory $script:workingRoot -TemplateId 'valid-template'

            $result | Should -HaveCount 1
            $result[0].Action | Should -Be 'Created'
            $result[0].Name | Should -Be 'Valid App - [IHD]'
            $script:invokeTemplateCallCount | Should -Be 1
        }
    }
}
