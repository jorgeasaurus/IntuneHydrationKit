function Get-HydrationGroupDefinitionsFromTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string[]]$Platforms
    )

    if (-not (Test-Path -Path $TemplatePath)) {
        return $null
    }

    if (@($Platforms).Count -eq 0) {
        return @{
            All            = @()
            Filtered       = @()
            DeleteFiltered = @()
        }
    }

    $allGroupDefs = @()
    $getChildItemParams = @{
        Path   = $TemplatePath
        Filter = '*.json'
        File   = $true
    }
    $templateFiles = Get-ChildItem @getChildItemParams
    foreach ($templateFile in $templateFiles) {
        try {
            $getContentParams = @{
                Path        = $templateFile.FullName
                Raw         = $true
                ErrorAction = 'Stop'
            }
            $content = Get-Content @getContentParams | ConvertFrom-Json -ErrorAction Stop
            $groups = if ($content.groups) { $content.groups } else { @($content) }
            $allGroupDefs += $groups
        } catch {
            Write-Warning "[Invoke-IntuneHydration] Failed to parse group template '$($templateFile.Name)': $($_.Exception.Message)"
        }
    }

    $filteredGroups = $allGroupDefs | Where-Object {
        $platform = if ($_.platform) { $_.platform } else { 'All' }
        ($Platforms -contains 'All') -or ($platform -eq 'All') -or ($platform -in $Platforms)
    }
    $deleteFilteredGroups = $allGroupDefs | Where-Object {
        $platform = if ($_.platform) { $_.platform } else { 'All' }
        ($Platforms -contains 'All') -or ($platform -in $Platforms)
    }

    return @{
        All            = $allGroupDefs
        Filtered       = @($filteredGroups)
        DeleteFiltered = @($deleteFilteredGroups)
    }
}
