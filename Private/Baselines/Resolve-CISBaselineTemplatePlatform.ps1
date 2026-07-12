function Resolve-CISBaselineTemplatePlatform {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object]$TemplateContent,

        [Parameter(Mandatory)]
        [System.IO.FileInfo]$TemplateFile,

        [Parameter(Mandatory)]
        [string]$BaselinePath,

        [Parameter(Mandatory)]
        [hashtable]$PlatformValueMapping
    )

    $platformValues = @($TemplateContent.platforms | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($platformValues.Count -gt 0) {
        $mappedPlatforms = foreach ($platformValue in $platformValues) {
            $PlatformValueMapping[[string]$platformValue]
        }
        return @($mappedPlatforms | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }

    $odataTypePlatformMap = @{
        '#microsoft.graph.windows10CompliancePolicy'             = 'Windows'
        '#microsoft.graph.windows81CompliancePolicy'             = 'Windows'
        '#microsoft.graph.windows10CustomConfiguration'           = 'Windows'
        '#microsoft.graph.windowsDeliveryOptimizationConfiguration' = 'Windows'
        '#microsoft.graph.windowsHealthMonitoringConfiguration'   = 'Windows'
        '#microsoft.graph.sharedPCConfiguration'                  = 'Windows'
        '#microsoft.graph.groupPolicyConfiguration'               = 'Windows'
        '#microsoft.graph.macOSCompliancePolicy'                  = 'macOS'
        '#microsoft.graph.iosCompliancePolicy'                    = 'iOS'
        '#microsoft.graph.androidCompliancePolicy'                = 'Android'
        '#microsoft.graph.androidWorkProfileCompliancePolicy'     = 'Android'
        '#microsoft.graph.androidDeviceOwnerCompliancePolicy'     = 'Android'
        '#microsoft.graph.deviceManagementCompliancePolicy'       = 'Linux'
    }

    $odataType = [string]$TemplateContent.'@odata.type'
    if ($odataTypePlatformMap.ContainsKey($odataType)) {
        return @($odataTypePlatformMap[$odataType])
    }

    $odataContext = [string]$TemplateContent.'@odata.context'
    $contextPlatformMap = @(
        @{ Pattern = '(?i)windows'; Platform = 'Windows' }
        @{ Pattern = '(?i)macOS|macos'; Platform = 'macOS' }
        @{ Pattern = '(?i)ios|iPadOS|ipad'; Platform = 'iOS' }
        @{ Pattern = '(?i)android'; Platform = 'Android' }
        @{ Pattern = '(?i)linux'; Platform = 'Linux' }
    )
    foreach ($contextHint in $contextPlatformMap) {
        if ($odataContext -match $contextHint.Pattern) {
            return @($contextHint.Platform)
        }
    }

    $rootPath = $BaselinePath
    $resolvedRoot = Resolve-Path -LiteralPath $BaselinePath -ErrorAction SilentlyContinue
    if ($resolvedRoot) {
        $rootPath = $resolvedRoot.Path
    }

    $relativePath = $TemplateFile.FullName
    if ($relativePath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $relativePath.Substring($rootPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }

    $templateName = if ($TemplateContent.name) { $TemplateContent.name } elseif ($TemplateContent.displayName) { $TemplateContent.displayName } else { $TemplateFile.BaseName }
    $searchText = "$relativePath`n$templateName"
    $platformHints = @(
        @{ Pattern = '(?i)(^|[/\\]|\s)macos(\s|[/\\]|$)|apple\s+macos|mac\s*os'; Platform = 'macOS' }
        @{ Pattern = '(?i)(^|[/\\]|\s)ios(\s|[/\\]|$)|iosipados|ipad'; Platform = 'iOS' }
        @{ Pattern = '(?i)android'; Platform = 'Android' }
        @{ Pattern = '(?i)linux'; Platform = 'Linux' }
        @{ Pattern = '(?i)(^|[/\\]|\s)windows(\s|[/\\]|$)|windows\s+11|windows\s+10|win11|win10|windows\s+cloud|cloud\s+pc|azure\s+virtual\s+desktop|avd|endpoint\s+protection|bitlocker|windows\s+hello|fido|defender\s+for\s+endpoint|mde\s+device\s+tag|attack\s+surface\s+reduction|visual\s+studio|vs\s+code|edge|chrome|intune\s+modern\s+workplace|account\s+protection|firewall'; Platform = 'Windows' }
    )

    foreach ($hint in $platformHints) {
        if ($searchText -match $hint.Pattern) {
            return @($hint.Platform)
        }
    }

    return @()
}
