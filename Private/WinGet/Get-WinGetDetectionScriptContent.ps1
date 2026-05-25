function Get-WinGetDetectionScriptContent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageIdentifier,

        [Parameter()]
        [string]$DisplayName,

        [Parameter()]
        [string]$Publisher
    )

    $escapedPackageIdentifier = $PackageIdentifier -replace "'", "''"
    $escapedPackageIdentifierPattern = [regex]::Escape($PackageIdentifier) -replace "'", "''"
    $escapedDisplayName = $DisplayName -replace "'", "''"
    $escapedPublisher = $Publisher -replace "'", "''"
    $bootstrapFragment = Get-WinGetBootstrapScriptFragment -LogFunctionName 'Write-WinGetDetectionLog' -BootstrapMessage 'Bootstrapping WinGet for detection.'

    return @"
`$PackageIdentifier = '$escapedPackageIdentifier'
`$PackageIdentifierPattern = '$escapedPackageIdentifierPattern'
`$DisplayName = '$escapedDisplayName'
`$Publisher = '$escapedPublisher'

function Write-WinGetDetectionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]`$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]`$Level = 'INFO'
    )

    Write-Output "[`$Level] `$Message"
}

$bootstrapFragment

function Test-InstalledApplicationRegistry {
    [CmdletBinding()]
    param()

    function Test-ApplicationPublisher {
        [CmdletBinding()]
        param(
            [Parameter()]
            [string]`$InstalledPublisher
        )

        if ([string]::IsNullOrWhiteSpace(`$Publisher)) {
            return `$true
        }

        if ([string]::IsNullOrWhiteSpace(`$InstalledPublisher)) {
            return `$false
        }

        return `$InstalledPublisher.IndexOf(`$Publisher, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }

    function Test-ApplicationDisplayName {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]`$InstalledDisplayName
        )

        `$namePatterns = @(`$PackageIdentifier)
        if (-not [string]::IsNullOrWhiteSpace(`$DisplayName)) {
            `$namePatterns += `$DisplayName
        }

        foreach (`$namePattern in `$namePatterns) {
            if ([string]::IsNullOrWhiteSpace(`$namePattern)) {
                continue
            }

            if (`$InstalledDisplayName.Equals(`$namePattern, [System.StringComparison]::OrdinalIgnoreCase)) {
                return `$true
            }

            if (`$InstalledDisplayName.StartsWith(`$namePattern, [System.StringComparison]::OrdinalIgnoreCase)) {
                return `$true
            }
        }

        return `$false
    }

    `$registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach (`$registryPath in `$registryPaths) {
        `$applications = Get-ItemProperty -Path `$registryPath -ErrorAction SilentlyContinue
        foreach (`$application in `$applications) {
            if ([string]::IsNullOrWhiteSpace(`$application.DisplayName)) {
                continue
            }

            if (-not (Test-ApplicationPublisher -InstalledPublisher `$application.Publisher)) {
                continue
            }

            if (Test-ApplicationDisplayName -InstalledDisplayName `$application.DisplayName) {
                Write-WinGetDetectionLog -Message "Detected '`$(`$application.DisplayName)' from uninstall registry."
                return `$true
            }
        }
    }

    return `$false
}

`$Winget = Get-WinGetExecutablePath
`$installed = & `$Winget list --id "`$PackageIdentifier" --exact --accept-source-agreements 2>&1
if (`$installed -match `$PackageIdentifierPattern) {
    Write-Output "`$PackageIdentifier is installed"
    exit 0
} elseif (Test-InstalledApplicationRegistry) {
    Write-Output "`$PackageIdentifier is installed"
    exit 0
} else {
    Write-Output "`$PackageIdentifier is not installed"
    exit 1
}
"@
}
