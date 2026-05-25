function Invoke-HydrationGroupStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepLabel,

        [Parameter(Mandatory)]
        [string]$GroupType,

        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string[]]$Platforms,

        [Parameter(Mandatory)]
        [bool]$RemoveExisting,

        [Parameter(Mandatory)]
        [bool]$WhatIfEnabled
    )

    $stepAction = if ($RemoveExisting) { 'Deleting' } else { 'Creating' }
    Write-HydrationLog -Message "${StepLabel}: $stepAction $GroupType Groups" -Level Info

    if ($RemoveExisting) {
        $knownNames = if (Test-Path -Path $TemplatePath) {
            $templateNameParams = @{
                Path          = $TemplatePath
                ArrayProperty = 'groups'
            }
            Get-TemplateDisplayNames @templateNameParams
        } else {
            $null
        }

        $deleteGroupParams = @{
            GroupType  = $GroupType
            Delete     = $true
            KnownNames = $knownNames
            WhatIf     = $WhatIfEnabled
        }
        $deleteResults = Invoke-GroupBatchImport @deleteGroupParams
        foreach ($result in $deleteResults) {
            if ($result.Name) {
                Write-HydrationLog -Message "  $($result.Action): $($result.Name)" -Level Info
            }
        }

        return $deleteResults
    }

    $groupDataParams = @{
        TemplatePath = $TemplatePath
        Platforms    = $Platforms
    }
    $groupData = Get-HydrationGroupDefinitionsFromTemplates @groupDataParams
    if ($null -eq $groupData) {
        Write-HydrationLog -Message "$GroupType Groups template directory not found" -Level Warning
        return @()
    }

    if ($groupData.Filtered.Count -lt $groupData.All.Count) {
        Write-HydrationLog -Message "  Filtered to $($groupData.Filtered.Count) of $($groupData.All.Count) groups based on platform selection: $($Platforms -join ', ')" -Level Info
    }

    $createGroupParams = @{
        GroupDefinitions = $groupData.Filtered
        GroupType        = $GroupType
        WhatIf           = $WhatIfEnabled
    }
    $groupResults = Invoke-GroupBatchImport @createGroupParams
    foreach ($result in $groupResults) {
        if ($result.Name) {
            Write-HydrationLog -Message "  $($result.Action): $($result.Name)" -Level Info
        }
    }

    return $groupResults
}
