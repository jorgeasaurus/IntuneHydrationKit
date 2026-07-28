function Sync-IntuneDeviceHealthScript {
    <#
    .SYNOPSIS
        Synchronizes one Intune device health script from a declarative definition.
    .DESCRIPTION
        Every definition requires DisplayName, Type, Path, SourceMarker, and
        OwnershipMetadata. Present definitions additionally require
        FingerprintMetadataKey, Fingerprint, Status, and BuildBody.
        BuildBody receives IncludeCreateOnlyProperties and remains workload-specific.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Definition,

        [Parameter()]
        [ValidateSet('Present', 'Remove')]
        [string]$DesiredState = 'Present',

        [Parameter()]
        [bool]$WhatIfEnabled = $false
    )

    $requiredKeys = @('DisplayName', 'Type', 'Path', 'SourceMarker', 'OwnershipMetadata')
    if ($DesiredState -eq 'Present') {
        $requiredKeys += 'FingerprintMetadataKey', 'Fingerprint', 'Status', 'BuildBody'
    }
    $missingKeys = @($requiredKeys | Where-Object { -not $Definition.ContainsKey($_) })
    if ($missingKeys.Count -gt 0) {
        throw "Device health script definition is missing required key(s): $($missingKeys -join ', ')"
    }
    if ($Definition.OwnershipMetadata -isnot [hashtable] -or $Definition.OwnershipMetadata.Count -eq 0) {
        throw 'Device health script definition requires non-empty ownership metadata.'
    }

    $escapedDisplayName = $Definition.DisplayName.Replace("'", "''")
    $filter = [uri]::EscapeDataString("displayName eq '$escapedDisplayName'")
    $response = Invoke-HydrationGraphRequest -Method GET -Uri "beta/deviceManagement/deviceHealthScripts?`$filter=$filter"
    $existingScripts = @($response.value | Where-Object { $null -ne $_ })
    $ownedScripts = [System.Collections.Generic.List[object]]::new()

    foreach ($existingScript in $existingScripts) {
        $description = [string]$existingScript.description
        if (-not (Test-HydrationKitObject -Description $description)) {
            continue
        }

        $descriptionLines = $description -split "`r?`n" | ForEach-Object { $_.Trim() }
        if ($descriptionLines -notcontains $Definition.SourceMarker) {
            continue
        }

        $metadata = ConvertFrom-HydrationDeviceHealthScriptDescription -Description $description
        $isOwned = $true
        foreach ($key in $Definition.OwnershipMetadata.Keys) {
            if (-not $metadata.ContainsKey($key) -or $metadata[$key] -cne [string]$Definition.OwnershipMetadata[$key]) {
                $isOwned = $false
                break
            }
        }

        if ($isOwned) {
            $ownedScripts.Add([pscustomobject]@{
                    Script   = $existingScript
                    Metadata = $metadata
                })
        }
    }

    if ($DesiredState -eq 'Remove') {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($ownedScript in $ownedScripts) {
            if ($WhatIfEnabled) {
                $results.Add((Add-HydrationDryRunResult -Action 'WouldDelete' -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type))
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($Definition.DisplayName, 'Delete remediation')) {
                continue
            }

            try {
                Invoke-HydrationGraphRequest -Method DELETE -Uri "beta/deviceManagement/deviceHealthScripts/$($ownedScript.Script.id)" | Out-Null
                Write-HydrationLog -Message "  Deleted: $($Definition.DisplayName)" -Level Info
                $results.Add((New-HydrationResult -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type -Action 'Deleted' -Status 'Removed'))
            } catch {
                $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
                Write-HydrationLog -Message "  Failed: $($Definition.DisplayName) - $errorMessage" -Level Warning
                $results.Add((New-HydrationResult -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type -Action 'Failed' -Status $errorMessage))
            }
        }

        return @($results)
    }

    if ($ownedScripts.Count -gt 1) {
        Write-HydrationLog -Message "  Failed: $($Definition.DisplayName) - Multiple matching hydration-owned remediations exist; remove them explicitly before importing." -Level Warning
        return @(New-HydrationResult -Name $Definition.DisplayName -Path $Definition.Path -Type $Definition.Type -Action 'Failed' -Status 'Multiple owned remediations')
    }

    $ownedScript = $ownedScripts | Select-Object -First 1
    if ($existingScripts.Count -gt 0 -and -not $ownedScript) {
        Write-HydrationLog -Message "  Failed: $($Definition.DisplayName) - A remediation with this name already exists but is not owned by Intune Hydration Kit." -Level Warning
        return @(New-HydrationResult -Name $Definition.DisplayName -Path $Definition.Path -Type $Definition.Type -Action 'Failed' -Status 'Name collision')
    }

    if ($ownedScript -and $ownedScript.Metadata[$Definition.FingerprintMetadataKey] -ceq $Definition.Fingerprint) {
        Write-HydrationLog -Message "  Skipped: $($Definition.DisplayName)" -Level Info
        return @(New-HydrationResult -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type -Action 'Skipped' -Status 'Already current')
    }

    if ($ownedScript -and $Definition.ContainsKey('RequireUnassigned') -and $Definition.RequireUnassigned) {
        try {
            $assignmentResponse = Invoke-HydrationGraphRequest -Method GET -Uri "beta/deviceManagement/deviceHealthScripts/$($ownedScript.Script.id)/assignments?`$top=1"
            $assignments = @($assignmentResponse.value | Where-Object { $null -ne $_ })
        } catch {
            $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $($Definition.DisplayName) - Could not verify assignments: $errorMessage" -Level Warning
            return @(New-HydrationResult -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type -Action 'Failed' -Status "Assignment check failed: $errorMessage")
        }

        if ($assignments.Count -gt 0) {
            Write-HydrationLog -Message "  Failed: $($Definition.DisplayName) - The remediation has assignments and will not be updated." -Level Warning
            return @(New-HydrationResult -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type -Action 'Failed' -Status 'Assigned')
        }
    }

    if ($WhatIfEnabled) {
        $action = if ($ownedScript) { 'WouldUpdate' } else { 'WouldCreate' }
        return @(Add-HydrationDryRunResult -Action $action -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type)
    }

    $operation = if ($ownedScript) { 'Update remediation' } else { 'Create remediation' }
    if (-not $PSCmdlet.ShouldProcess($Definition.DisplayName, $operation)) {
        return @()
    }

    try {
        $body = & $Definition.BuildBody (-not $ownedScript)
        if ($ownedScript) {
            Invoke-HydrationGraphRequest -Method PATCH -Uri "beta/deviceManagement/deviceHealthScripts/$($ownedScript.Script.id)" -Body $body | Out-Null
            Write-HydrationLog -Message "  Updated: $($Definition.DisplayName)" -Level Info
            return @(New-HydrationResult -Name $Definition.DisplayName -Id $ownedScript.Script.id -Path $Definition.Path -Type $Definition.Type -Action 'Updated' -Status $Definition.Status)
        }

        $createdScript = Invoke-HydrationGraphRequest -Method POST -Uri 'beta/deviceManagement/deviceHealthScripts' -Body $body
        Write-HydrationLog -Message "  Created: $($Definition.DisplayName)" -Level Info
        return @(New-HydrationResult -Name $Definition.DisplayName -Id $createdScript.id -Path $Definition.Path -Type $Definition.Type -Action 'Created' -Status $Definition.Status)
    } catch {
        $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
        Write-HydrationLog -Message "  Failed: $($Definition.DisplayName) - $errorMessage" -Level Warning
        return @(New-HydrationResult -Name $Definition.DisplayName -Path $Definition.Path -Type $Definition.Type -Action 'Failed' -Status $errorMessage)
    }
}
