function Sync-IntuneWinGetProactiveRemediation {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [psobject[]]$Templates,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [bool]$WhatIfEnabled = $false
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $definitions = @(
        Get-WinGetRemediationDefinition -Scope 'system' -TemplateSet $Templates
        Get-WinGetRemediationDefinition -Scope 'user' -TemplateSet $Templates
    )

    $availability = Get-IntuneProactiveRemediationAvailability
    if (-not $availability.IsAvailable) {
        Write-HydrationLog -Message "  Skipped: WinGet proactive remediations - $($availability.Message)" -Level Warning
        return @(
            New-HydrationResult -Name 'WinGet proactive remediations' -Type 'WinGetRemediation' -Action 'Skipped' -Status $availability.Status
        )
    }

    foreach ($winGetDefinition in $definitions) {
        $hasPackages = $winGetDefinition.PackageIdentifiers.Count -gt 0
        $definition = @{
            DisplayName       = $winGetDefinition.DisplayName
            Type              = 'WinGetRemediation'
            Path              = $null
            SourceMarker      = 'Imported from WinGet'
            OwnershipMetadata = @{ WinGetRemediationScope = $winGetDefinition.Scope }
        }
        if (-not $RemoveExisting -and $hasPackages) {
            $definition.FingerprintMetadataKey = 'WinGetPackageFingerprint'
            $definition.Fingerprint = Get-WinGetRemediationFingerprint -PackageIdentifiers $winGetDefinition.PackageIdentifiers
            $definition.Status = "Packages=$($winGetDefinition.PackageIdentifiers.Count)"
            $definition.BuildBody = {
                param($IncludeCreateOnlyProperties)
                New-WinGetRemediationBody -Definition $winGetDefinition -IncludeCreateOnlyProperties $IncludeCreateOnlyProperties
            }
        }
        $desiredState = if ($RemoveExisting -or -not $hasPackages) { 'Remove' } else { 'Present' }

        $definitionResults = @(Sync-IntuneDeviceHealthScript -Definition $definition -DesiredState $desiredState -WhatIfEnabled $WhatIfEnabled)
        foreach ($result in $definitionResults) {
            $results.Add($result)
        }

        if (-not $RemoveExisting -and -not $hasPackages -and $definitionResults.Count -eq 0) {
            Write-HydrationLog -Message "  Skipped: $($winGetDefinition.DisplayName) - No packages." -Level Info
            $results.Add((New-HydrationResult -Name $winGetDefinition.DisplayName -Type 'WinGetRemediation' -Action 'Skipped' -Status 'No packages'))
        }
    }

    return @($results)
}
