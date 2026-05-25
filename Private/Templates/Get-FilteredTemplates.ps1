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
    [OutputType([System.IO.FileInfo[]])]
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

    function Get-DirectoryAncestorNames {
        param(
            [Parameter(Mandatory)]
            [string]$DirectoryPath
        )

        $directoryNames = [System.Collections.Generic.List[string]]::new()
        $currentPath = $DirectoryPath

        while (-not [string]::IsNullOrWhiteSpace($currentPath)) {
            $leafName = Split-Path -Path $currentPath -Leaf
            if (-not [string]::IsNullOrWhiteSpace($leafName)) {
                $directoryNames.Add($leafName)
            }

            $parentPath = Split-Path -Path $currentPath -Parent
            if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $currentPath) {
                break
            }

            $currentPath = $parentPath
        }

        return $directoryNames
    }

    function Get-FirstDirectoryUnderRoot {
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter(Mandatory)]
            [string]$DirectoryPath
        )

        $normalizedRootPath = $RootPath.TrimEnd([char[]]@('/', '\'))
        $currentPath = $DirectoryPath

        while (-not [string]::IsNullOrWhiteSpace($currentPath)) {
            $leafName = Split-Path -Path $currentPath -Leaf
            $parentPath = Split-Path -Path $currentPath -Parent

            if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $currentPath) {
                break
            }

            $normalizedParentPath = $parentPath.TrimEnd([char[]]@('/', '\'))
            if ($normalizedParentPath.Equals($normalizedRootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $leafName
            }

            $currentPath = $parentPath
        }

        return $null
    }

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
                    $platformDirectory = Get-FirstDirectoryUnderRoot -RootPath $Path -DirectoryPath $template.DirectoryName
                    $matched = $platformDirectory -eq $plat -or
                    ($plat -eq 'macOS' -and $platformDirectory -eq 'Mac')
                }
                'Folder' {
                    # OpenIntuneBaseline uses uppercase folder names: WINDOWS, WINDOWS365, MACOS, BYOD
                    $directoryNames = Get-DirectoryAncestorNames -DirectoryPath $template.DirectoryName
                    $matched = switch ($plat) {
                        'Windows' { ($directoryNames -match '^WINDOWS(365)?$').Count -gt 0 }
                        'macOS' { ($directoryNames -match '^MACOS$').Count -gt 0 }
                        'iOS' { ($directoryNames -contains 'BYOD') -and $template.Name -match 'iOS' }
                        'Android' { ($directoryNames -contains 'BYOD') -and $template.Name -match 'Android' }
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
