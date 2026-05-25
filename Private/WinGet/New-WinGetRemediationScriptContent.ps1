function New-WinGetRemediationScriptContent {
    param(
        [Parameter(Mandatory)]
        [string[]]$PackageIdentifiers,

        [Parameter(Mandatory)]
        [ValidateSet('system', 'user')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateSet('Detection', 'Remediation')]
        [string]$ScriptType
    )

    $escapedPackageIdentifiers = @(
        $PackageIdentifiers |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique |
            ForEach-Object { "'{0}'" -f (($_ -replace "'", "''")) }
    )

    $allowListLiteral = if ($escapedPackageIdentifiers.Count -gt 0) {
        "@({0})" -f ($escapedPackageIdentifiers -join ', ')
    } else {
        '@()'
    }

    $wingetScope = if ($Scope -eq 'system') { 'machine' } else { 'user' }
    $scopeLabel = if ($Scope -eq 'system') { 'System' } else { 'User' }
    $logOperation = if ($ScriptType -eq 'Detection') { 'Detect' } else { 'Remediate' }
    $bootstrapFragment = Get-WinGetBootstrapScriptFragment -LogFunctionName 'Write-RemediationLog' -BootstrapMessage 'Bootstrapping WinGet for proactive remediation.'
    $scriptSuffix = if ($ScriptType -eq 'Detection') {
        @"
`$pendingUpgrades = [System.Collections.Generic.List[string]]::new()
foreach (`$packageIdentifier in `$packageIdentifiers) {
    `$escapedPackageIdentifier = [regex]::Escape(`$packageIdentifier)
    if (`$upgradeOutput -match `$escapedPackageIdentifier) {
        Write-RemediationLog -Message "Upgrade available for `$packageIdentifier."
        `$pendingUpgrades.Add(`$packageIdentifier)
    }
}

if (`$pendingUpgrades.Count -gt 0) {
    Write-RemediationLog -Message "Pending upgrades: `$(`$pendingUpgrades -join ', ')"
    exit 1
}

Write-RemediationLog -Message 'No upgrades needed.'
exit 0
"@
    } else {
        @"
`$completedUpgrades = [System.Collections.Generic.List[string]]::new()
`$failedUpgrades = [System.Collections.Generic.List[string]]::new()
foreach (`$packageIdentifier in `$packageIdentifiers) {
    `$escapedPackageIdentifier = [regex]::Escape(`$packageIdentifier)
    if (`$upgradeOutput -notmatch `$escapedPackageIdentifier) {
        continue
    }

    Write-RemediationLog -Message "Upgrade available for `$packageIdentifier. Starting remediation."
    & `$wingetPath upgrade --id "`$packageIdentifier" --exact --silent --force --scope `$scope --accept-package-agreements --accept-source-agreements 2>&1 | Out-String | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace(`$_)) {
            Write-RemediationLog -Message `$_
        }
    }

    `$exitCode = `$LASTEXITCODE
    if (`$exitCode -eq 0 -or `$exitCode -eq -1978335189) {
        `$completedUpgrades.Add(`$packageIdentifier)
        Write-RemediationLog -Message "Upgrade completed for `$packageIdentifier with exit code `$exitCode."
    } else {
        `$failedUpgrades.Add("`$packageIdentifier (`$exitCode)")
        Write-RemediationLog -Message "Upgrade failed for `$packageIdentifier with exit code `$exitCode." -Level 'WARN'
    }
}

if (`$failedUpgrades.Count -gt 0) {
    Write-RemediationLog -Message "Failed upgrades: `$(`$failedUpgrades -join ', ')" -Level 'ERROR'
    exit 1
}

if (`$completedUpgrades.Count -gt 0) {
    Write-RemediationLog -Message "Completed upgrades: `$(`$completedUpgrades -join ', ')"
} else {
    Write-RemediationLog -Message 'No upgrades were applicable during remediation.'
}

exit 0
"@
    }

    return @"
`$ErrorActionPreference = 'Stop'
`$packageIdentifiers = $allowListLiteral
`$scope = '$wingetScope'
`$scopeLabel = '$scopeLabel'

function Get-IntuneManagementExtensionLogDirectory {
    [CmdletBinding()]
    param()

    `$programDataPath = if (-not [string]::IsNullOrWhiteSpace(`$env:ProgramData)) {
        `$env:ProgramData
    } else {
        'C:\ProgramData'
    }

    `$logDirectory = Join-Path -Path `$programDataPath -ChildPath 'Microsoft\IntuneManagementExtension\Logs'
    if (-not (Test-Path -Path `$logDirectory)) {
        `$null = New-Item -Path `$logDirectory -ItemType Directory -Force
    }

    return `$logDirectory
}

function Write-RemediationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]`$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]`$Level = 'INFO'
    )

    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    `$entry = "[`$timestamp] [`$Level] `$Message"
    Add-Content -Path `$script:logPath -Value `$entry
    Write-Output `$entry
}

`$logDirectory = Get-IntuneManagementExtensionLogDirectory
`$script:logPath = Join-Path -Path `$logDirectory -ChildPath "IntuneHydrationKit-WinGet-Remediation-$scopeLabel-$logOperation.log"

Write-RemediationLog -Message "Starting WinGet proactive remediation $ScriptType for `$scopeLabel scope."
Write-RemediationLog -Message "Allowlist contains `$(`$packageIdentifiers.Count) package identifier(s)."

$bootstrapFragment

`$wingetPath = Get-WinGetExecutablePath
Write-RemediationLog -Message "Resolved winget executable: `$wingetPath"

`$upgradeOutput = & `$wingetPath upgrade --scope `$scope --accept-source-agreements 2>&1 | Out-String
Write-RemediationLog -Message "Upgrade scan completed for `$scopeLabel scope."
"@ + [Environment]::NewLine + $scriptSuffix
}
