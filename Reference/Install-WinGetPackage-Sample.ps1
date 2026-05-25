# Sample WinGet install wrapper generated from current IntuneHydrationKit logic.
# Replace command/package values as needed for your package.
$ErrorActionPreference = 'Stop'
$packageIdentifier = 'PuTTY.PuTTY'
$operationName = 'Install'

function Get-IntuneManagementExtensionLogDirectory {
    [CmdletBinding()]
    param()

    $programDataPath = if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        $env:ProgramData
    } else {
        'C:\ProgramData'
    }

    $logDirectory = Join-Path -Path $programDataPath -ChildPath 'Microsoft\IntuneManagementExtension\Logs'
    if (-not (Test-Path -Path $logDirectory)) {
        $null = New-Item -Path $logDirectory -ItemType Directory -Force
    }

    return $logDirectory
}

function Get-WinGetWrapperLogFileName {
    [CmdletBinding()]
    param()

    $safePackageIdentifier = ($packageIdentifier -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safePackageIdentifier)) {
        $safePackageIdentifier = 'package'
    }

    return "IntuneHydrationKit-WinGet-$operationName-$safePackageIdentifier.log"
}

function Write-WinGetWrapperLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $script:logPath -Value "`[$timestamp`] `[$Level`] $Message"
}

function Write-WinGetProcessStreamToLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if (-not (Test-Path -Path $Path)) {
        return
    }

    $lines = @(Get-Content -Path $Path -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) {
        return
    }

    Write-WinGetWrapperLog -Message "${Label}:" -Level $Level
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        Write-WinGetWrapperLog -Message $line -Level $Level
    }
}

function Test-WinGetAlreadyInstalledNoUpgradeOutput {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Output
    )

    $outputText = ($Output -join [Environment]::NewLine)
    $foundExistingPackage = $outputText -match 'Found an existing package already installed\. Trying to upgrade the installed package'
    $noUpgradeAvailable = $outputText -match 'No available upgrade found' -or
    $outputText -match 'No newer package versions are available'

    return $foundExistingPackage -and $noUpgradeAvailable
}

function Get-WinGetExecutablePath {
    [CmdletBinding()]
    param()

    $programDataWingetRoot = Join-Path -Path $env:ProgramData -ChildPath 'Microsoft.DesktopAppInstaller'
    $programDataWingetExe = Join-Path -Path $programDataWingetRoot -ChildPath 'winget.exe'
    $isSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -eq 'NT AUTHORITY\SYSTEM'

    function Test-WinGetExecutable {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            return $false
        }

        try {
            $versionOutput = & $Path --version 2>&1
            return $LASTEXITCODE -eq 0 -or $versionOutput -match 'v?\d+\.\d+'
        } catch {
            return $false
        }
    }

    function Install-WinGetSystemBootstrap {
        [CmdletBinding()]
        param()

        function Get-AppInstallerMsixPath {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Path
            )

            foreach ($filter in @('AppInstaller*_x64*.msix', 'AppInstaller*.msix')) {
                $msixPath = Get-ChildItem -Path $Path -Filter $filter -File -ErrorAction SilentlyContinue |
                    Sort-Object -Property Name -Descending |
                    Select-Object -First 1

                if ($msixPath) {
                    return $msixPath
                }
            }

            throw 'Unable to locate App Installer MSIX payload inside the downloaded bundle.'
        }

        $stagingRoot = Join-Path -Path $env:TEMP -ChildPath 'IntuneHydrationKit-WinGetBootstrap'
        $bundlePath = Join-Path -Path $stagingRoot -ChildPath 'Microsoft.DesktopAppInstaller.msixbundle'
        $bundleExtractPath = Join-Path -Path $stagingRoot -ChildPath 'bundle'
        $msixExtractPath = Join-Path -Path $stagingRoot -ChildPath 'appinstaller'
        $vcRedistPath = Join-Path -Path $stagingRoot -ChildPath 'vc_redist.x64.exe'

        Write-WinGetWrapperLog -Message 'Bootstrapping WinGet for SYSTEM context.'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        if (Test-Path -Path $stagingRoot) {
            Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        foreach ($directoryPath in @($stagingRoot, $bundleExtractPath, $msixExtractPath)) {
            $null = New-Item -Path $directoryPath -ItemType Directory -Force
        }

        try {
            Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcRedistPath -UseBasicParsing -TimeoutSec 120
            $vcRedist = Start-Process -FilePath $vcRedistPath -ArgumentList '/q /norestart' -Wait -PassThru
            Write-WinGetWrapperLog -Message "VC++ bootstrap exited with code $($vcRedist.ExitCode)."
        } catch {
            Write-WinGetWrapperLog -Message "VC++ bootstrap failed: $($_.Exception.Message)" -Level 'WARN'
        }

        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath -UseBasicParsing -TimeoutSec 120
        [System.IO.Compression.ZipFile]::ExtractToDirectory($bundlePath, $bundleExtractPath)
        $msixPath = Get-AppInstallerMsixPath -Path $bundleExtractPath

        if (Test-Path -Path $programDataWingetRoot) {
            Remove-Item -Path $programDataWingetRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        $null = New-Item -Path $programDataWingetRoot -ItemType Directory -Force
        [System.IO.Compression.ZipFile]::ExtractToDirectory($msixPath.FullName, $msixExtractPath)
        Copy-Item -Path (Join-Path -Path $msixExtractPath -ChildPath '*') -Destination $programDataWingetRoot -Recurse -Force
        Write-WinGetWrapperLog -Message "Bootstrapped WinGet to '$programDataWingetRoot'."
    }

    if (Test-WinGetExecutable -Path $programDataWingetExe) {
        return $programDataWingetExe
    }

    if (-not $isSystem) {
        $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
        if ($command -and -not [string]::IsNullOrWhiteSpace($command.Source) -and (Test-WinGetExecutable -Path $command.Source)) {
            return $command.Source
        }

        $searchPatterns = @(
            (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'),
            (Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe')
        )

        if (${env:ProgramFiles(x86)}) {
            $searchPatterns += Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe'
        }

        foreach ($pattern in $searchPatterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                continue
            }

            $candidateFiles = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Sort-Object -Property FullName -Descending)
            if ($candidateFiles.Count -gt 0 -and (Test-WinGetExecutable -Path $candidateFiles[0].FullName)) {
                return $candidateFiles[0].FullName
            }
        }
    }

    Install-WinGetSystemBootstrap
    if (Test-WinGetExecutable -Path $programDataWingetExe) {
        return $programDataWingetExe
    }

    throw 'winget.exe could not be located or bootstrapped successfully for this context.'
}

$wingetCommand = 'winget install --id PuTTY.PuTTY --exact --silent --scope machine --accept-package-agreements --accept-source-agreements'
$argumentString = ($wingetCommand -replace '^\s*winget(?:\.exe)?\s*', '').Trim()
if ([string]::IsNullOrWhiteSpace($argumentString)) {
    throw "Unable to derive WinGet arguments from command '$wingetCommand'."
}

$logDirectory = Get-IntuneManagementExtensionLogDirectory
$logFileName = Get-WinGetWrapperLogFileName
$script:logPath = Join-Path -Path $logDirectory -ChildPath $logFileName
$baseLogName = [System.IO.Path]::GetFileNameWithoutExtension($logFileName)
$stdoutPath = Join-Path -Path $logDirectory -ChildPath "$baseLogName.stdout.log"
$stderrPath = Join-Path -Path $logDirectory -ChildPath "$baseLogName.stderr.log"

foreach ($streamPath in @($stdoutPath, $stderrPath)) {
    if (Test-Path -Path $streamPath) {
        Remove-Item -Path $streamPath -Force -ErrorAction SilentlyContinue
    }
}

Write-WinGetWrapperLog -Message "Starting $operationName for package '$packageIdentifier'."
Write-WinGetWrapperLog -Message "Resolved IME log path: $script:logPath"
Write-WinGetWrapperLog -Message "Executing WinGet command: $wingetCommand"

try {
    $wingetPath = Get-WinGetExecutablePath
    Write-WinGetWrapperLog -Message "Resolved winget executable: $wingetPath"
    $process = Start-Process -FilePath $wingetPath -ArgumentList $argumentString -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    Write-WinGetProcessStreamToLog -Path $stdoutPath -Label 'WinGet standard output'
    Write-WinGetProcessStreamToLog -Path $stderrPath -Label 'WinGet standard error' -Level 'WARN'
    $standardOutput = if (Test-Path -Path $stdoutPath) { @(Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue) } else { @() }
    $exitCode = [int]$process.ExitCode
    Write-WinGetWrapperLog -Message "WinGet process exited with code $exitCode."
    if ($operationName -eq 'Install' -and ($exitCode -eq -1978335189 -or (Test-WinGetAlreadyInstalledNoUpgradeOutput -Output $standardOutput))) {
        Write-WinGetWrapperLog -Message "Package already installed (no upgrade needed). Treating as success." -Level 'INFO'
        $exitCode = 0
    }
    exit $exitCode
} catch {
    Write-WinGetProcessStreamToLog -Path $stdoutPath -Label 'WinGet standard output'
    Write-WinGetProcessStreamToLog -Path $stderrPath -Label 'WinGet standard error' -Level 'WARN'
    Write-WinGetWrapperLog -Message "Wrapper execution failed: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
