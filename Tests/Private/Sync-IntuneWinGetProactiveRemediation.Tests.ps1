#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Get-Module -Name IntuneHydrationKit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
    $script:TestModule = Get-Module -Name IntuneHydrationKit | Select-Object -First 1
}

Describe 'Sync-IntuneWinGetProactiveRemediation' {
    BeforeEach {
        InModuleScope IntuneHydrationKit {
            $script:HydrationMarker = 'Imported by Intune Hydration Kit'
        }
        $script:generatedScriptsRoot = Join-Path ([System.IO.Path]::GetTempPath()) "WinGetRemediationScripts-$([guid]::NewGuid().ToString('N'))"
        InModuleScope IntuneHydrationKit -Parameters @{ GeneratedScriptsPath = $script:generatedScriptsRoot } {
            param($GeneratedScriptsPath)
            $script:GeneratedScriptsPath = $GeneratedScriptsPath
            $script:GeneratedScriptsNoticeWritten = $false
            $script:HydrationSessionId = 'test-session'
        }

        $script:testTemplates = @(
            [pscustomobject]@{
                templateId        = 'contoso-machine'
                packageIdentifier = 'Contoso.Machine'
                package           = [pscustomobject]@{
                    match = [pscustomobject]@{
                        scope = 'machine'
                    }
                }
            },
            [pscustomobject]@{
                templateId        = 'contoso-user'
                packageIdentifier = 'Contoso.User'
                package           = [pscustomobject]@{
                    match = [pscustomobject]@{
                        scope = 'user'
                    }
                }
            }
        )

        Mock Write-HydrationLog { } -ModuleName IntuneHydrationKit
        Mock Get-IntuneProactiveRemediationAvailability {
            [pscustomobject]@{
                IsAvailable = $true
                Status      = 'Available'
                Message     = 'Proactive remediations are available.'
            }
        } -ModuleName IntuneHydrationKit
        Mock Invoke-HydrationGraphRequest {
            param($Method, $Uri, $Body)

            switch ($Method) {
                'GET' {
                    return @{
                        value = @()
                    }
                }
                'POST' {
                    if ($Uri -eq 'beta/deviceManagement/deviceHealthScripts') {
                        if (-not $script:postedRemediationBodies) {
                            $script:postedRemediationBodies = @()
                        }

                        $script:postedRemediationBodies += $Body
                        return @{ id = "remediation-$($script:postedRemediationBodies.Count)" }
                    }
                }
                'PATCH' {
                    $script:patchedRemediationUri = $Uri
                    $script:patchedRemediationBody = $Body
                    return @{}
                }
                'DELETE' {
                    if (-not $script:deletedRemediationUris) {
                        $script:deletedRemediationUris = @()
                    }

                    $script:deletedRemediationUris += $Uri
                    return @{}
                }
            }
        } -ModuleName IntuneHydrationKit

        $script:postedRemediationBodies = @()
        $script:patchedRemediationUri = $null
        $script:patchedRemediationBody = $null
        $script:deletedRemediationUris = @()
    }

    AfterEach {
        if (Test-Path -Path $script:generatedScriptsRoot) {
            Remove-Item -Path $script:generatedScriptsRoot -Recurse -Force
        }

        InModuleScope IntuneHydrationKit {
            $script:GeneratedScriptsPath = $null
            $script:GeneratedScriptsNoticeWritten = $false
            $script:HydrationSessionId = $null
        }
    }

    It 'Should create system and user proactive remediations for the selected templates' {
        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates
        } $script:testTemplates

        $result | Should -HaveCount 2
        $result.Action | Should -Be @('Created', 'Created')

        $script:postedRemediationBodies | Should -HaveCount 2
        $script:postedRemediationBodies[0].displayName | Should -Be 'WinGet App Updates (System)'
        $script:postedRemediationBodies[0].runAsAccount | Should -Be 'system'
        $script:postedRemediationBodies[0].isGlobalScript | Should -Be $false
        $script:postedRemediationBodies[0].description | Should -BeLike '*Imported by Intune Hydration Kit*'
        $script:postedRemediationBodies[0].description | Should -BeLike '*Imported from WinGet*'
        $script:postedRemediationBodies[1].displayName | Should -Be 'WinGet App Updates (User)'
        $script:postedRemediationBodies[1].runAsAccount | Should -Be 'user'

        $systemDetection = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script:postedRemediationBodies[0].detectionScriptContent))
        $userRemediation = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script:postedRemediationBodies[1].remediationScriptContent))

        $systemDetection | Should -Match "Contoso\.Machine"
        $systemDetection | Should -Match "\$scope = 'machine'"
        $systemDetection | Should -Match 'upgrade --scope \$scope'
        $userRemediation | Should -Match "Contoso\.User"
        $userRemediation | Should -Match "\$scope = 'user'"
        $userRemediation | Should -Match 'upgrade --id "\$packageIdentifier".*--scope \$scope'
        $userRemediation | Should -Match 'Microsoft\\IntuneManagementExtension\\Logs'
        $userRemediation | Should -Match 'IntuneHydrationKit\\Logs'
        $userRemediation | Should -Match 'Get-HydrationWinGetLogDirectory'
        $userRemediation | Should -Not -Match 'Get-IntuneManagementExtensionLogDirectory'
        (Join-Path $script:generatedScriptsRoot 'WinGetRemediations/System/Detect-WinGetAppUpdates.ps1') | Should -Exist
        (Join-Path $script:generatedScriptsRoot 'WinGetRemediations/User/Remediate-WinGetAppUpdates.ps1') | Should -Exist
    }

    It 'Should skip when the proactive remediation feature is unavailable' {
        Mock Get-IntuneProactiveRemediationAvailability {
            [pscustomobject]@{
                IsAvailable = $false
                Status      = 'FeatureUnavailable'
                Message     = 'Device health scripts are not available in this tenant.'
            }
        } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates
        } $script:testTemplates

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Skipped'
        $result[0].Status | Should -Be 'FeatureUnavailable'

        @($script:postedRemediationBodies).Count | Should -Be 0
    }

    It 'Should skip when permissions are insufficient' {
        Mock Get-IntuneProactiveRemediationAvailability {
            [pscustomobject]@{
                IsAvailable = $false
                Status      = 'InsufficientPermissions'
                Message     = 'Insufficient permissions to access device health scripts.'
            }
        } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates
        } $script:testTemplates

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Skipped'
        $result[0].Status | Should -Be 'InsufficientPermissions'

        @($script:postedRemediationBodies).Count | Should -Be 0
    }

    It 'Should skip WhatIf mode when proactive remediation availability is missing' {
        Mock Get-IntuneProactiveRemediationAvailability {
            [pscustomobject]@{
                IsAvailable = $false
                Status      = 'FeatureUnavailable'
                Message     = 'Device health scripts are not available in this tenant.'
            }
        } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates -WhatIfEnabled $true
        } $script:testTemplates

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Skipped'
        $result[0].Status | Should -Be 'FeatureUnavailable'

        Should -Invoke Invoke-HydrationGraphRequest -Exactly 0 -ModuleName IntuneHydrationKit
    }

    It 'Should update an owned remediation when the package fingerprint changes' {
        Mock Invoke-HydrationGraphRequest {
            param($Method, $Uri, $Body)

            switch ($Method) {
                'GET' {
                    return @{
                        value = @(
                            @{
                                id          = 'existing-system'
                                displayName = 'WinGet App Updates (System)'
                                description = "Auto-update remediation for WinGet apps (system scope).`nImported by Intune Hydration Kit`nImported from WinGet`nWinGetRemediationScope: system`nWinGetPackageCount: 1`nWinGetPackageFingerprint: OLDHASH"
                            }
                        )
                    }
                }
                'PATCH' {
                    $script:patchedRemediationUri = $Uri
                    $script:patchedRemediationBody = $Body
                    return @{}
                }
            }
        } -ModuleName IntuneHydrationKit -ParameterFilter { $Method -in @('GET', 'PATCH') }

        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates
        } @(
            [pscustomobject]@{
                templateId        = 'contoso-machine'
                packageIdentifier = 'Contoso.Machine'
                package           = [pscustomobject]@{
                    match = [pscustomobject]@{
                        scope = 'machine'
                    }
                }
            }
        )

        $result[0].Action | Should -Be 'Updated'

        $script:patchedRemediationUri | Should -Be 'beta/deviceManagement/deviceHealthScripts/existing-system'
        $script:patchedRemediationBody.description | Should -Not -BeLike '*OLDHASH*'
        $script:patchedRemediationBody.ContainsKey('isGlobalScript') | Should -Be $false
        $script:patchedRemediationBody.ContainsKey('@odata.type') | Should -Be $false
    }

    It 'Should delete an owned remediation when the current template set has no packages for its scope' {
        Mock Invoke-HydrationGraphRequest {
            param($Method, $Uri, $Body)

            switch ($Method) {
                'GET' {
                    if ($Uri -like '*User*') {
                        return @{
                            value = @(
                                @{
                                    id          = 'existing-user'
                                    displayName = 'WinGet App Updates (User)'
                                    description = "Imported by Intune Hydration Kit`nImported from WinGet`nWinGetRemediationScope: user`nWinGetPackageFingerprint: STALE"
                                }
                            )
                        }
                    }

                    return @{
                        value = @()
                    }
                }
                'POST' {
                    $script:postedRemediationBodies += $Body
                    return @{ id = 'created-system' }
                }
                'DELETE' {
                    $script:deletedRemediationUris += $Uri
                    return @{}
                }
            }
        } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates
        } @(
            [pscustomobject]@{
                templateId        = 'contoso-machine'
                packageIdentifier = 'Contoso.Machine'
                package           = [pscustomobject]@{
                    match = [pscustomobject]@{
                        scope = 'machine'
                    }
                }
            }
        )

        $result.Action | Should -Be @('Created', 'Deleted')
        $script:deletedRemediationUris | Should -Contain 'beta/deviceManagement/deviceHealthScripts/existing-user'
    }

    It 'Should mark empty remediation scopes skipped when no owned remediation exists' {
        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates
        } @(
            [pscustomobject]@{
                templateId        = 'contoso-machine'
                packageIdentifier = 'Contoso.Machine'
                package           = [pscustomobject]@{
                    match = [pscustomobject]@{
                        scope = 'machine'
                    }
                }
            }
        )

        $result.Action | Should -Contain 'Skipped'
        ($result | Where-Object { $_.Name -eq 'WinGet App Updates (User)' }).Status | Should -Be 'No packages'
    }

    It 'Should delete owned proactive remediations during remove mode' {
        Mock Invoke-HydrationGraphRequest {
            param($Method, $Uri)

            switch ($Method) {
                'GET' {
                    if ($Uri -like '*System*') {
                        return @{
                            value = @(
                                @{
                                    id          = 'system-id'
                                    displayName = 'WinGet App Updates (System)'
                                    description = "Imported by Intune Hydration Kit`nImported from WinGet`nWinGetRemediationScope: system"
                                }
                            )
                        }
                    }

                    return @{
                        value = @(
                            @{
                                id          = 'user-id'
                                displayName = 'WinGet App Updates (User)'
                                description = "Imported by Intune Hydration Kit`nImported from WinGet`nWinGetRemediationScope: user"
                            }
                        )
                    }
                }
                'DELETE' {
                    if (-not $script:deletedRemediationUris) {
                        $script:deletedRemediationUris = @()
                    }

                    $script:deletedRemediationUris += $Uri
                    return @{}
                }
            }
        } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates -RemoveExisting
        } $script:testTemplates

        $result | Should -HaveCount 2
        $result.Action | Should -Be @('Deleted', 'Deleted')

        $script:deletedRemediationUris | Should -Contain 'beta/deviceManagement/deviceHealthScripts/system-id'
        $script:deletedRemediationUris | Should -Contain 'beta/deviceManagement/deviceHealthScripts/user-id'
    }

    It 'Should return failed remediation results instead of throwing when delete is unauthorized' {
        Mock Invoke-HydrationGraphRequest {
            param($Method, $Uri)

            switch ($Method) {
                'GET' {
                    if ($Uri -like '*System*') {
                        return @{
                            value = @(
                                @{
                                    id          = 'system-id'
                                    displayName = 'WinGet App Updates (System)'
                                    description = "Imported by Intune Hydration Kit`nImported from WinGet`nWinGetRemediationScope: system"
                                }
                            )
                        }
                    }

                    return @{ value = @() }
                }
                'DELETE' {
                    throw 'HTTP/2.0 403 Forbidden {"error":{"code":"UnknownError","message":"User is not authorized to perform this operation"}}'
                }
            }
        } -ModuleName IntuneHydrationKit

        $result = & $script:TestModule {
            param([object[]]$Templates)
            Sync-IntuneWinGetProactiveRemediation -Templates $Templates -RemoveExisting
        } $script:testTemplates

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Failed'
        $result[0].Type | Should -Be 'WinGetRemediation'
        $result[0].Status | Should -Match '403|not authorized|UnknownError'
    }
}
