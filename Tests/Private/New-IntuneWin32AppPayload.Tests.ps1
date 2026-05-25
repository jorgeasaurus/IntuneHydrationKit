#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Utilities/Get-ConfigurationSection.ps1
    . $PSScriptRoot/../../Private/Utilities/Resolve-MinimumSupportedOperatingSystem.ps1
    . $PSScriptRoot/../../Private/Utilities/Resolve-ApplicableArchitecture.ps1
    . $PSScriptRoot/../../Private/Utilities/ConvertTo-HydrationBoolValue.ps1
    . $PSScriptRoot/../../Private/WinGet/ConvertTo-IntuneWinDetectionRule.ps1
    . $PSScriptRoot/../../Private/WinGet/ConvertTo-IntuneWinRequirementRule.ps1
    . $PSScriptRoot/../../Private/WinGet/New-IntuneWin32AppPayload.ps1
}

Describe 'New-IntuneWin32AppPayload' {
    BeforeAll {
        $script:artifactRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/New-IntuneWin32AppPayload'
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }

        $null = New-Item -Path $script:artifactRoot -ItemType Directory -Force
        'Write-Output ''detected''' | Set-Content -Path (Join-Path $script:artifactRoot 'detection.ps1')
        'Write-Output ''requirement''' | Set-Content -Path (Join-Path $script:artifactRoot 'requirement.ps1')
    }

    AfterAll {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
    }

    It 'Should build a win32LobApp payload with mapped rules and defaults' {
        $payload = New-IntuneWin32AppPayload -Configuration @{
            PackageInformation    = @{ SetupFile = 'setup.exe' }
            Information           = @{
                DisplayName     = 'Contoso App'
                Description     = 'Line of business app'
                Publisher       = 'Contoso'
                AppVersion      = '1.0.0'
                Notes           = 'Notes'
                RoleScopeTagIds = @('1', '2')
            }
            Program               = @{
                InstallCommand          = 'setup.exe /install'
                UninstallCommand        = 'setup.exe /uninstall'
                InstallExperience       = 'system'
                DeviceRestartBehavior   = 'suppress'
                AllowAvailableUninstall = 'true'
            }
            RequirementRule       = @{
                MinimumRequiredOperatingSystem = 'W10_22H2'
                Architecture                   = 'x64'
                MinimumFreeDiskSpaceInMB       = 1024
                MinimumMemoryInMB              = 2048
            }
            DetectionRule         = @(
                @{ DetectionType = 'Script'; ScriptFile = 'detection.ps1'; EnforceSignatureCheck = 'false'; RunAs32Bit = 'false' }
            )
            CustomRequirementRule = @(
                @{ RequirementType = 'Script'; ScriptFile = 'requirement.ps1'; Value = '1' }
            )
        } -PackageFileName 'app.intunewin' -SetupFilePath 'setup.exe' -IconBase64 'ZmFrZS1pY29u' -ScriptRootPath $script:artifactRoot

        $payload['@odata.type'] | Should -Be '#microsoft.graph.win32LobApp'
        $payload.displayName | Should -Be 'Contoso App'
        $payload.fileName | Should -Be 'app.intunewin'
        $payload.setupFilePath | Should -Be 'setup.exe'
        $payload.deviceRestartBehavior | Should -Be 'suppress'
        $payload.allowAvailableUninstall | Should -BeTrue
        $payload.applicableArchitectures | Should -Be 'x64'
        $payload.minimumSupportedOperatingSystem.v10_21H1 | Should -BeTrue
        $payload.ContainsKey('minimumSupportedWindowsRelease') | Should -BeFalse
        $payload.minimumFreeDiskSpaceInMB | Should -Be 1024
        $payload.minimumMemoryInMB | Should -Be 2048
        $payload.roleScopeTagIds | Should -Be @('1', '2')
        $payload.rules | Should -HaveCount 2
        $payload.ContainsKey('detectionRules') | Should -BeFalse
        $payload.ContainsKey('requirementRules') | Should -BeFalse
        $payload.largeIcon.value | Should -Be 'ZmFrZS1pY29u'
    }

    It 'Should omit optional architecture when set to All' {
        $payload = New-IntuneWin32AppPayload -Configuration @{
            Information     = @{ DisplayName = 'Contoso App' }
            Program         = @{ InstallCommand = 'setup.exe'; UninstallCommand = 'setup.exe /remove' }
            RequirementRule = @{ Architecture = 'All' }
        }

        $payload.ContainsKey('applicableArchitectures') | Should -BeFalse
    }

    It 'Should map Windows 10 20H2 to the Graph minimum OS key' {
        $payload = New-IntuneWin32AppPayload -Configuration @{
            Information     = @{ DisplayName = 'Contoso App' }
            Program         = @{ InstallCommand = 'setup.exe'; UninstallCommand = 'setup.exe /remove' }
            RequirementRule = @{ MinimumRequiredOperatingSystem = 'W10_20H2' }
        }

        $payload.minimumSupportedOperatingSystem.v10_20H2 | Should -BeTrue
        $payload.minimumSupportedOperatingSystem.PSObject.Properties.Name | Should -Not -Contain 'v10_2H20'
    }

    It 'Should normalize blank optional URLs to null' {
        $payload = New-IntuneWin32AppPayload -Configuration @{
            Information = @{
                DisplayName    = 'Contoso App'
                InformationURL = '   '
                PrivacyURL     = ''
            }
            Program     = @{ InstallCommand = 'setup.exe'; UninstallCommand = 'setup.exe /remove' }
        }

        $payload.informationUrl | Should -BeNullOrEmpty
        $payload.privacyInformationUrl | Should -BeNullOrEmpty
    }
}
