# Sample WinGet detection script generated from current IntuneHydrationKit logic.
# Replace PackageIdentifier as needed for your package.
$PackageIdentifier = 'PuTTY.PuTTY'
$PackageIdentifierPattern = 'PuTTY\.PuTTY'

function Write-WinGetDetectionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    Write-Host "[$Level] $Message"
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

        Write-WinGetDetectionLog -Message 'Bootstrapping WinGet for detection.'
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
            Write-WinGetDetectionLog -Message "VC++ bootstrap exited with code $($vcRedist.ExitCode)."
        } catch {
            Write-WinGetDetectionLog -Message "VC++ bootstrap failed: $($_.Exception.Message)" -Level 'WARN'
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
        Write-WinGetDetectionLog -Message "Bootstrapped WinGet to '$programDataWingetRoot'."
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

$Winget = Get-WinGetExecutablePath
$installed = & $Winget list --id "$PackageIdentifier" --source winget --accept-source-agreements 2>&1
if ($installed -match $PackageIdentifierPattern) {
    Write-Host "$PackageIdentifier is installed"
    exit 0
} else {
    Write-Host "$PackageIdentifier is not installed"
    exit 1
}
