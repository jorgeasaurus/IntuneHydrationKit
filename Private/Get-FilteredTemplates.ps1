function Get-FilteredTemplates {
    <#
    .SYNOPSIS
        Gets template files from a directory with optional platform filtering
    .DESCRIPTION
        Internal helper function that retrieves JSON template files from a specified path
        and optionally filters them by platform using various filtering strategies.
    .PARAMETER Path
        The directory path to search for template files
    .PARAMETER Platform
        Array of platforms to filter by. Valid values: Windows, macOS, iOS, Android, Linux, All
        Defaults to 'All' which returns all templates without filtering.
    .PARAMETER FilterMode
        The filtering strategy to use:
        - Prefix: Filter by filename prefix (e.g., Windows-*, macOS-*)
        - Suffix: Filter by filename suffix (e.g., *-iOS.json, *-Android.json)
        - Directory: Filter by parent directory name (e.g., Windows/, macOS/)
        - Folder: Filter by OpenIntuneBaseline OS folder structure
    .PARAMETER Recurse
        If specified, searches subdirectories recursively
    .PARAMETER ResourceType
        The type of resource being loaded (for logging purposes)
    #>
    [CmdletBinding()]
    param(
        [string]$Path,

        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')]
        [string[]]$Platform = @('All'),

        [Parameter()]
        [ValidateSet('Prefix', 'Suffix', 'Directory', 'Folder')]
        [string]$FilterMode = 'Prefix',

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [string]$ResourceType = "template"
    )

    # Get all templates first
    $allTemplates = Get-HydrationTemplates -Path $Path -Recurse:$Recurse -ResourceType $ResourceType

    # Return everything if no filtering needed
    if (-not $Platform -or $Platform -contains 'All' -or -not $allTemplates -or $allTemplates.Count -eq 0) {
        return $allTemplates
    }

    Write-Verbose "Filtering $($allTemplates.Count) templates for platforms: $($Platform -join ', ') using $FilterMode mode"

    $filteredTemplates = foreach ($template in $allTemplates) {
        $matched = $false

        foreach ($plat in $Platform) {
            if ($matched) { break }

            switch ($FilterMode) {
                'Prefix' {
                    # PowerShell -like is case-insensitive by default
                    $matched = $template.Name -like "$plat[-_]*" -or
                    ($plat -eq 'Windows' -and $template.Name -like "Win[-_]*") -or
                    ($plat -eq 'macOS' -and $template.Name -like "mac[-_]*")
                }
                'Suffix' {
                    $matched = $template.Name -like "*[-_]$plat.json"
                }
                'Directory' {
                    $parentDir = Split-Path -Path $template.DirectoryName -Leaf
                    $matched = $parentDir -eq $plat -or
                    ($plat -eq 'macOS' -and $parentDir -eq 'Mac')
                }
                'Folder' {
                    # OpenIntuneBaseline uses uppercase folder names: WINDOWS, WINDOWS365, MACOS, BYOD
                    $pathParts = $template.DirectoryName -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
                    $matched = switch ($plat) {
                        'Windows' { ($pathParts -match '^WINDOWS(365)?$').Count -gt 0 }
                        'macOS' { ($pathParts -match '^MACOS$').Count -gt 0 }
                        'iOS' { ($pathParts -contains 'BYOD') -and $template.Name -match 'iOS' }
                        'Android' { ($pathParts -contains 'BYOD') -and $template.Name -match 'Android' }
                        default { $false }
                    }
                }
            }
        }

        if ($matched) { $template }
    }

    Write-Verbose "Filtered to $($filteredTemplates.Count) $ResourceType template(s) for platforms: $($Platform -join ', ')"

    return $filteredTemplates
}
