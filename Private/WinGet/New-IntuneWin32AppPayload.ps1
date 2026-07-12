function New-IntuneWin32AppPayload {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration,

        [Parameter()]
        [string]$PackageFileName,

        [Parameter()]
        [string]$SetupFilePath,

        [Parameter()]
        [string]$IconBase64,

        [Parameter()]
        [string]$IconMimeType = 'image/png',

        [Parameter()]
        [string]$ScriptRootPath
    )

    $packageInformation = Get-ConfigurationSection -InputObject $Configuration -Name 'PackageInformation'
    $information = Get-ConfigurationSection -InputObject $Configuration -Name 'Information'
    $program = Get-ConfigurationSection -InputObject $Configuration -Name 'Program'
    $requirementConfig = Get-ConfigurationSection -InputObject $Configuration -Name 'RequirementRule'

    $detectionRules = @(foreach ($rule in @($Configuration.DetectionRule)) {
            if ($null -ne $rule) {
                ConvertTo-IntuneWinDetectionRule -Rule $rule -ScriptRootPath $ScriptRootPath
            }
        })

    $requirementRules = @(foreach ($rule in @($Configuration.CustomRequirementRule)) {
            if ($null -ne $rule) {
                ConvertTo-IntuneWinRequirementRule -Rule $rule -ScriptRootPath $ScriptRootPath
            }
        })

    $packageName = if ($PackageFileName) {
        $PackageFileName
    } elseif ($packageInformation.SetupFile) {
        $packageInformation.SetupFile
    } else {
        $null
    }

    $setupFile = if ($SetupFilePath) {
        $SetupFilePath
    } elseif ($packageInformation.SetupFile) {
        $packageInformation.SetupFile
    } else {
        $null
    }

    $payload = @{
        '@odata.type'                   = '#microsoft.graph.win32LobApp'
        displayName                     = $information.DisplayName
        description                     = ($information.Description ?? '')
        publisher                       = ($information.Publisher ?? '')
        developer                       = ($information.Developer ?? '')
        owner                           = ($information.Owner ?? '')
        notes                           = ($information.Notes ?? '')
        appVersion                      = ($information.AppVersion ?? '')
        informationUrl                  = if ([string]::IsNullOrWhiteSpace($information.InformationURL)) { $null } else { $information.InformationURL }
        privacyInformationUrl           = if ([string]::IsNullOrWhiteSpace($information.PrivacyURL)) { $null } else { $information.PrivacyURL }
        fileName                        = $packageName
        setupFilePath                   = $setupFile
        installCommandLine              = $program.InstallCommand
        uninstallCommandLine            = $program.UninstallCommand
        minimumSupportedOperatingSystem = Resolve-MinimumSupportedOperatingSystem -Release ($requirementConfig.MinimumSupportedWindowsRelease ?? $requirementConfig.MinimumRequiredOperatingSystem)
        installExperience               = @{ runAsAccount = ($program.InstallExperience ?? 'system') }
        minimumFreeDiskSpaceInMB        = ($requirementConfig.MinimumFreeDiskSpaceInMB ?? $null)
        minimumMemoryInMB               = ($requirementConfig.MinimumMemoryInMB ?? $null)
        returnCodes                     = @(
            @{ returnCode = 0; type = 'success' }
            @{ returnCode = 1707; type = 'success' }
            @{ returnCode = 3010; type = 'softReboot' }
            @{ returnCode = 1641; type = 'hardReboot' }
            @{ returnCode = 1618; type = 'retry' }
        )
    }

    $applicableArchitecture = Resolve-ApplicableArchitecture -Architecture $requirementConfig.Architecture
    if ($applicableArchitecture) {
        $payload.applicableArchitectures = $applicableArchitecture
    }

    if ($program.DeviceRestartBehavior) {
        $payload.deviceRestartBehavior = $program.DeviceRestartBehavior
    }

    if ($program.ContainsKey('AllowAvailableUninstall')) {
        $payload.allowAvailableUninstall = ConvertTo-HydrationBoolValue -Value $program.AllowAvailableUninstall
    }

    if ($information.ContainsKey('RoleScopeTagIds') -and @($information.RoleScopeTagIds).Count -gt 0) {
        $payload.roleScopeTagIds = @($information.RoleScopeTagIds)
    }

    if ($IconBase64) {
        $payload.largeIcon = @{
            '@odata.type' = '#microsoft.graph.mimeContent'
            type          = $IconMimeType
            value         = $IconBase64
        }
    }

    $combinedRules = @($detectionRules + $requirementRules)
    if ($combinedRules.Count -gt 0) {
        $payload.rules = $combinedRules
    }

    Write-Debug "Created Win32 app payload for '$($payload.displayName)' with FileName='$($payload.fileName)', SetupFilePath='$($payload.setupFilePath)', AppVersion='$($payload.appVersion)', DetectionRules=$($detectionRules.Count), RequirementRules=$($requirementRules.Count), CombinedRules=$($combinedRules.Count), RoleScopeTags=$(@($payload.roleScopeTagIds).Count), HasIcon=$([bool]$IconBase64)."

    return $payload
}
