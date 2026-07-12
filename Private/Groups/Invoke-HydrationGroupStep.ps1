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
    $logParams = @{
        Message = "${StepLabel}: $stepAction $GroupType Groups"
        Level   = 'Info'
    }
    Write-HydrationLog @logParams

    if (@($Platforms).Count -eq 0) {
        Write-Verbose "No $GroupType groups in scope for the selected platform filter"
        return @()
    }

    $groupData = Get-HydrationGroupDefinitionsFromTemplates -TemplatePath $TemplatePath -Platforms $Platforms
    if ($null -eq $groupData) {
        $logParams = @{
            Message = "$GroupType Groups template directory not found"
            Level   = 'Warning'
        }
        Write-HydrationLog @logParams
        return @()
    }

    if ($RemoveExisting) {
        $knownNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($group in $groupData.DeleteFiltered) {
            if ($group.displayName) {
                [void]$knownNames.Add($group.displayName)
            }
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
                $logParams = @{
                    Message = "  $($result.Action): $($result.Name)"
                    Level   = 'Info'
                }
                Write-HydrationLog @logParams
            }
        }

        return $deleteResults
    }

    if ($groupData.Filtered.Count -lt $groupData.All.Count) {
        $logParams = @{
            Message = "  Filtered to $($groupData.Filtered.Count) of $($groupData.All.Count) groups based on platform selection: $($Platforms -join ', ')"
            Level   = 'Info'
        }
        Write-HydrationLog @logParams
    }

    $createGroupParams = @{
        GroupDefinitions = $groupData.Filtered
        GroupType        = $GroupType
        WhatIf           = $WhatIfEnabled
    }
    $groupResults = Invoke-GroupBatchImport @createGroupParams
    foreach ($result in $groupResults) {
        if ($result.Name) {
            $logParams = @{
                Message = "  $($result.Action): $($result.Name)"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams
        }
    }

    return $groupResults
}
