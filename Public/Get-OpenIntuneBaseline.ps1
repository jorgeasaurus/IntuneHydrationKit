function Get-OpenIntuneBaseline {
    <#
    .SYNOPSIS
        Downloads OpenIntuneBaseline repository from GitHub
    .DESCRIPTION
        Downloads and extracts the OpenIntuneBaseline repository containing all baseline policies
    .PARAMETER RepoUrl
        GitHub repository URL (default: https://github.com/SkipToTheEndpoint/OpenIntuneBaseline)
    .PARAMETER Branch
        Branch to download (default: main)
    .PARAMETER DestinationPath
        Path to extract the repository (default: temp directory)
    .EXAMPLE
        Get-OpenIntuneBaseline -DestinationPath ./Baselines
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RepoUrl = "https://github.com/SkipToTheEndpoint/OpenIntuneBaseline",

        [Parameter()]
        [string]$Branch = "main",

        [Parameter()]
        [string]$DestinationPath
    )

    if (-not $DestinationPath) {
        $DestinationPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OpenIntuneBaseline"
    }

    $zipUrl = "$RepoUrl/archive/refs/heads/$Branch.zip"
    $zipPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OpenIntuneBaseline-$Branch.zip"

    try {
        Write-Host "Downloading OpenIntuneBaseline from $zipUrl" -InformationAction Continue

        # Download the repository
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop

        # Clean existing directory if present (always execute, not affected by WhatIf)
        if (Test-Path -Path $DestinationPath) {
            Remove-Item -Path $DestinationPath -Recurse -Force -WhatIf:$false
        }

        # Extract
        Expand-Archive -Path $zipPath -DestinationPath $DestinationPath -Force -WhatIf:$false

        # The archive extracts to a subfolder, move contents up
        $extractedFolder = Get-ChildItem -Path $DestinationPath -Directory | Select-Object -First 1
        if ($extractedFolder) {
            $tempMove = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OIB-temp-$(Get-Random)"
            Move-Item -Path $extractedFolder.FullName -Destination $tempMove -WhatIf:$false
            Remove-Item -Path $DestinationPath -Force -Recurse -WhatIf:$false
            Move-Item -Path $tempMove -Destination $DestinationPath -WhatIf:$false
        }

        # Clean up zip
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue -WhatIf:$false

        Write-Host "OpenIntuneBaseline downloaded to: $DestinationPath" -InformationAction Continue

        return $DestinationPath
    }
    catch {
        Write-Error "Failed to download OpenIntuneBaseline: $_"
        throw
    }
}