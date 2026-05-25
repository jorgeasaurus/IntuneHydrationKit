function Save-HydrationGeneratedScript {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter()]
        [AllowNull()]
        [string]$Content,

        [Parameter()]
        [string]$SourcePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'RelativePath is required.'
    }

    if ([string]::IsNullOrWhiteSpace($Content) -and [string]::IsNullOrWhiteSpace($SourcePath)) {
        throw 'Either Content or SourcePath must be provided.'
    }

    if (-not $script:GeneratedScriptsPath) {
        $sessionId = if ([string]::IsNullOrWhiteSpace($script:HydrationSessionId)) {
            Get-Date -Format 'yyyyMMdd-HHmmss'
        } else {
            $script:HydrationSessionId
        }

        $tempBase = [System.IO.Path]::GetTempPath()
        $script:GeneratedScriptsPath = Join-Path -Path $tempBase -ChildPath "IntuneHydrationKit/GeneratedScripts/$sessionId"
    }

    if (-not (Test-Path -LiteralPath $script:GeneratedScriptsPath)) {
        New-Item -Path $script:GeneratedScriptsPath -ItemType Directory -Force -WhatIf:$false -ErrorAction Stop | Out-Null
    }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw 'RelativePath must not be rooted.'
    }

    $generatedScriptsRoot = [System.IO.Path]::GetFullPath($script:GeneratedScriptsPath)
    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path -Path $generatedScriptsRoot -ChildPath $RelativePath))
    $rootWithSeparator = if ($generatedScriptsRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or $generatedScriptsRoot.EndsWith([System.IO.Path]::AltDirectorySeparatorChar)) {
        $generatedScriptsRoot
    } else {
        $generatedScriptsRoot + [System.IO.Path]::DirectorySeparatorChar
    }

    if (-not $destinationPath.StartsWith($rootWithSeparator, [System.StringComparison]::Ordinal)) {
        throw 'RelativePath must stay within the generated scripts directory.'
    }

    $destinationDirectory = Split-Path -Path $destinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -Path $destinationDirectory -ItemType Directory -Force -WhatIf:$false -ErrorAction Stop | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
            throw "SourcePath must be an existing file: $SourcePath"
        }

        Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Force -WhatIf:$false -ErrorAction Stop
    } else {
        Set-Content -LiteralPath $destinationPath -Value $Content -Encoding utf8 -WhatIf:$false -ErrorAction Stop
    }

    if (-not $script:GeneratedScriptsNoticeWritten) {
        Write-HydrationLog -Message "Generated PowerShell scripts saved to: $($script:GeneratedScriptsPath)" -Level Info
        $script:GeneratedScriptsNoticeWritten = $true
    }

    return $destinationPath
}
