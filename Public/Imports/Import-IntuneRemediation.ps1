function Import-IntuneRemediation {
    <#
    .SYNOPSIS
        Imports bundled Proactive Intune Remediations.
    .DESCRIPTION
        Creates or updates unassigned Windows remediation packages from the bundled
        Proactive remediation templates. Only resources tagged with the matching
        template ID and hydration marker are eligible for deletion.
    .PARAMETER TemplatePath
        Directory containing remediation template metadata and scripts.
    .PARAMETER TemplateId
        Optional remediation template IDs to import.
    .PARAMETER RemoveExisting
        Deletes matching hydration-owned remediation packages instead of creating them.
    .EXAMPLE
        Import-IntuneRemediation
    .EXAMPLE
        Import-IntuneRemediation -TemplateId 'windows-disk-pressure-cleanup' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$TemplatePath = (Join-Path -Path $script:TemplatesPath -ChildPath 'Remediations'),

        [Parameter()]
        [string[]]$TemplateId,

        [Parameter()]
        [switch]$RemoveExisting
    )

    $templates = @(Get-HydrationRemediationTemplates -TemplatePath $TemplatePath -TemplateId $TemplateId)
    if ($templates.Count -eq 0) {
        if ($TemplateId) {
            Write-Warning "No remediation templates matched TemplateId value(s): $($TemplateId -join ', ')"
        }
        return @()
    }

    $availability = Get-IntuneProactiveRemediationAvailability
    if (-not $availability.IsAvailable) {
        Write-HydrationLog -Message "  Skipped: Proactive remediations - $($availability.Message)" -Level Warning
        return @(New-HydrationResult -Name 'Proactive remediations' -Type 'Remediation' -Action 'Skipped' -Status $availability.Status)
    }

    $operation = if ($RemoveExisting) { 'Delete' } else { 'Import' }
    if (-not $WhatIfPreference -and -not $PSCmdlet.ShouldProcess("$($templates.Count) remediation package(s)", $operation)) {
        return @()
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($template in $templates) {
        $displayName = "$script:ImportPrefix$($template.DisplayName)"
        $definition = @{
            DisplayName       = $displayName
            Type              = 'Remediation'
            Path              = $template.TemplatePath
            SourceMarker      = 'Imported from Proactive Remediation Pack'
            OwnershipMetadata = @{ RemediationTemplateId = $template.TemplateId }
            RequireUnassigned = $true
        }
        if (-not $RemoveExisting) {
            $fingerprint = Get-HydrationRemediationFingerprint -Template $template
            $definition.FingerprintMetadataKey = 'RemediationFingerprint'
            $definition.Fingerprint = $fingerprint
            $definition.Status = "Template=$($template.TemplateId)"
            $definition.BuildBody = {
                param($IncludeCreateOnlyProperties)
                $description = New-HydrationRemediationDescription -Template $template -Fingerprint $fingerprint
                New-HydrationRemediationBody -Template $template -DisplayName $displayName -Description $description -IncludeCreateOnlyProperties $IncludeCreateOnlyProperties
            }
        }
        $desiredState = if ($RemoveExisting) { 'Remove' } else { 'Present' }

        foreach ($result in @(Sync-IntuneDeviceHealthScript -Definition $definition -DesiredState $desiredState -WhatIfEnabled $WhatIfPreference -Confirm:$false)) {
            $results.Add($result)
        }
    }

    return @($results)
}
