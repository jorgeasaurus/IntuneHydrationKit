function Select-WinGetPackageInstaller {
    <#
    .SYNOPSIS
        Selects the best installer from resolved WinGet package metadata.
    .DESCRIPTION
        Applies deterministic scoring so future Win32 packaging can resolve the same
        installer on any PowerShell 7 platform without shelling out to winget.
    .PARAMETER Installer
        Installer entries from a resolved WinGet package manifest.
    .PARAMETER Architecture
        Preferred architecture.
    .PARAMETER Scope
        Preferred install scope.
    .PARAMETER InstallerLocale
        Preferred installer locale.
    .PARAMETER InstallerType
        Preferred installer type.
    .OUTPUTS
        PSCustomObject representing the selected installer.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Installer,

        [Parameter()]
        [string]$Architecture = 'x64',

        [Parameter()]
        [string]$Scope = 'machine',

        [Parameter()]
        [string]$InstallerLocale,

        [Parameter()]
        [string]$InstallerType
    )

    $scoredInstallers = foreach ($currentInstaller in $Installer) {
        $score = 0

        if ($Architecture) {
            if ($currentInstaller.Architecture -eq $Architecture) {
                $score += 100
            } elseif ($currentInstaller.Architecture -eq 'neutral') {
                $score += 50
            } else {
                $score -= 25
            }
        }

        if ($Scope) {
            if ([string]::IsNullOrWhiteSpace($currentInstaller.Scope)) {
                $score += 5
            } elseif ($currentInstaller.Scope -eq $Scope) {
                $score += 40
            } else {
                $score -= 10
            }
        }

        if ($InstallerLocale) {
            if ($currentInstaller.InstallerLocale -eq $InstallerLocale) {
                $score += 20
            } elseif ([string]::IsNullOrWhiteSpace($currentInstaller.InstallerLocale)) {
                $score += 5
            }
        }

        if ($InstallerType) {
            if ($currentInstaller.InstallerType -eq $InstallerType) {
                $score += 15
            } elseif ([string]::IsNullOrWhiteSpace($currentInstaller.InstallerType)) {
                $score += 5
            }
        }

        Write-Debug "WinGet installer candidate scored $score with preferences Architecture='$Architecture', Scope='$Scope', InstallerLocale='$InstallerLocale', InstallerType='$InstallerType': $(Format-WinGetInstallerSummary -Installer $currentInstaller)."

        [PSCustomObject]@{
            Score     = $score
            Installer = $currentInstaller
        }
    }

    $selectedInstaller = $scoredInstallers |
        Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{
            Expression = {
                if ($_.Installer.Architecture -eq $Architecture) {
                    0
                } elseif ($_.Installer.Architecture -eq 'neutral') {
                    1
                } else {
                    2
                }
            }
        }, @{
            Expression = {
                if ($_.Installer.Scope -eq $Scope) {
                    0
                } elseif ([string]::IsNullOrWhiteSpace($_.Installer.Scope)) {
                    1
                } else {
                    2
                }
            }
        }, @{
            Expression = {
                if ($_.Installer.InstallerType) {
                    0
                } else {
                    1
                }
            }
        } |
        Select-Object -First 1 -ExpandProperty Installer

    if (-not $selectedInstaller) {
        throw 'No WinGet installers were available for selection.'
    }

    Write-Debug "Selected WinGet installer: $(Format-WinGetInstallerSummary -Installer $selectedInstaller)."

    return $selectedInstaller
}
