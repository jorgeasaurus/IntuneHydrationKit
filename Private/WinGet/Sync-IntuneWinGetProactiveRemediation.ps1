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

    function Get-ExistingRemediation {
        param(
            [Parameter(Mandatory)]
            [string]$DisplayName
        )

        $escapedDisplayName = $DisplayName.Replace("'", "''")
        $filter = [uri]::EscapeDataString("displayName eq '$escapedDisplayName'")
        $response = Invoke-HydrationGraphRequest -Method GET -Uri "beta/deviceManagement/deviceHealthScripts?`$filter=$filter"
        return @($response.value)
    }

    function Test-OwnedWinGetRemediation {
        param(
            [Parameter(Mandatory)]
            [psobject]$ExistingRemediation,

            [Parameter(Mandatory)]
            [string]$Scope
        )

        return (Test-HydrationKitObject -Description ([string]$ExistingRemediation.description)) -and
        ([string]$ExistingRemediation.description -like '*Imported from WinGet*') -and
        ([string]$ExistingRemediation.description -like "*WinGetRemediationScope: $Scope*")
    }

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

    foreach ($definition in $definitions) {
        $existingRemediations = Get-ExistingRemediation -DisplayName $definition.DisplayName
        $ownedExisting = @($existingRemediations | Where-Object { Test-OwnedWinGetRemediation -ExistingRemediation $_ -Scope $definition.Scope })

        if ($RemoveExisting) {
            if ($ownedExisting.Count -eq 0) {
                continue
            }

            if ($WhatIfEnabled) {
                foreach ($existingRemediation in $ownedExisting) {
                    $results.Add((Add-HydrationDryRunResult -Action 'WouldDelete' -Name $definition.DisplayName -Id $existingRemediation.id -Type 'WinGetRemediation'))
                }
                continue
            }

            foreach ($existingRemediation in $ownedExisting) {
                Invoke-HydrationGraphRequest -Method DELETE -Uri "beta/deviceManagement/deviceHealthScripts/$($existingRemediation.id)" | Out-Null
                Write-HydrationLog -Message "  Deleted: $($definition.DisplayName)" -Level Info
                $results.Add((New-HydrationResult -Name $definition.DisplayName -Id $existingRemediation.id -Type 'WinGetRemediation' -Action 'Deleted' -Status 'Removed'))
            }
            continue
        }

        if ($definition.PackageIdentifiers.Count -eq 0) {
            continue
        }

        $ownedExistingRemediation = $ownedExisting | Select-Object -First 1
        if ($existingRemediations.Count -gt 0 -and -not $ownedExistingRemediation) {
            Write-HydrationLog -Message "  Failed: $($definition.DisplayName) - A remediation with this name already exists but is not owned by Intune Hydration Kit." -Level Warning
            $results.Add((New-HydrationResult -Name $definition.DisplayName -Type 'WinGetRemediation' -Action 'Failed' -Status 'Name collision'))
            continue
        }

        $fingerprint = Get-WinGetRemediationFingerprint -PackageIdentifiers $definition.PackageIdentifiers
        if ($ownedExistingRemediation -and [string]$ownedExistingRemediation.description -like "*WinGetPackageFingerprint: $fingerprint*") {
            Write-HydrationLog -Message "  Skipped: $($definition.DisplayName)" -Level Info
            $results.Add((New-HydrationResult -Name $definition.DisplayName -Id $ownedExistingRemediation.id -Type 'WinGetRemediation' -Action 'Skipped' -Status 'Already current'))
            continue
        }

        if ($WhatIfEnabled) {
            $action = if ($ownedExistingRemediation) { 'WouldUpdate' } else { 'WouldCreate' }
            $results.Add((Add-HydrationDryRunResult -Action $action -Name $definition.DisplayName -Id $ownedExistingRemediation.id -Type 'WinGetRemediation'))
            continue
        }

        $body = New-WinGetRemediationBody -Definition $definition -IncludeCreateOnlyProperties (-not $ownedExistingRemediation)
        if ($ownedExistingRemediation) {
            Invoke-HydrationGraphRequest -Method PATCH -Uri "beta/deviceManagement/deviceHealthScripts/$($ownedExistingRemediation.id)" -Body $body | Out-Null
            Write-HydrationLog -Message "  Updated: $($definition.DisplayName)" -Level Info
            $results.Add((New-HydrationResult -Name $definition.DisplayName -Id $ownedExistingRemediation.id -Type 'WinGetRemediation' -Action 'Updated' -Status "Packages=$($definition.PackageIdentifiers.Count)"))
        } else {
            $createdRemediation = Invoke-HydrationGraphRequest -Method POST -Uri 'beta/deviceManagement/deviceHealthScripts' -Body $body
            Write-HydrationLog -Message "  Created: $($definition.DisplayName)" -Level Info
            $results.Add((New-HydrationResult -Name $definition.DisplayName -Id $createdRemediation.id -Type 'WinGetRemediation' -Action 'Created' -Status "Packages=$($definition.PackageIdentifiers.Count)"))
        }
    }

    return @($results)
}
