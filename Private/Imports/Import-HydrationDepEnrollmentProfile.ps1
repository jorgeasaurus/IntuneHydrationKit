function Import-HydrationDepEnrollmentProfile {
    <#
    .SYNOPSIS
        Creates a macOS DEP enrollment profile from a template.
    .DESCRIPTION
        Skips creation when any profile with a matching prefixed or legacy name
        exists under any DEP token, or when no Apple DEP token is configured.
    .PARAMETER Template
        Parsed enrollment template object.
    .PARAMETER ProfileName
        Prefixed profile display name.
    .PARAMETER TemplateBaseName
        Legacy unprefixed template name.
    .OUTPUTS
        Hydration result objects.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template,

        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter()]
        [string]$TemplateBaseName
    )

    try {
        $existingDEP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/depOnboardingSettings" -ErrorAction Stop

        # Flatten profiles across all DEP tokens, then apply the canonical match policy
        $allDepProfiles = @()
        foreach ($depToken in $existingDEP.value) {
            $depProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/depOnboardingSettings/$($depToken.id)/enrollmentProfiles" -ErrorAction SilentlyContinue
            if ($depProfiles.value) {
                $allDepProfiles += @($depProfiles.value)
            }
        }
        $existingMatch = Select-HydrationExistingMatch -Candidates $allDepProfiles -Name $ProfileName -LegacyName $TemplateBaseName -PreferTagged

        if ($existingMatch) {
            Write-HydrationLog -Message "  Skipped: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'MacOSDEPEnrollmentProfile' -Id $existingMatch.id -Action 'Skipped' -Status 'Already exists'
        }

        if ($existingDEP.value.Count -eq 0) {
            Write-HydrationLog -Message "  Skipped: $ProfileName - No Apple DEP token configured" -Level Warning
            return New-HydrationResult -Name $ProfileName -Type 'MacOSDEPEnrollmentProfile' -Action 'Skipped' -Status 'No DEP token configured'
        }

        if (-not $PSCmdlet.ShouldProcess($ProfileName, "Create macOS DEP enrollment profile")) {
            Write-HydrationLog -Message "  WouldCreate: $ProfileName" -Level Info
            return New-HydrationResult -Name $ProfileName -Type 'MacOSDEPEnrollmentProfile' -Action 'WouldCreate' -Status 'DryRun'
        }

        # Apply prefix and hydration tag
        $Template.displayName = $ProfileName
        $Template.description = New-HydrationDescription -ExistingText $Template.description

        $jsonBody = $Template | ConvertTo-Json -Depth 10

        # Create profile under the first DEP token
        $depTokenId = $existingDEP.value[0].id
        $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/depOnboardingSettings/$depTokenId/enrollmentProfiles" -Body $jsonBody -ContentType "application/json" -OutputType PSObject -ErrorAction Stop

        Write-HydrationLog -Message "  Created: $ProfileName" -Level Info
        return New-HydrationResult -Name $ProfileName -Type 'MacOSDEPEnrollmentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
    } catch {
        Write-HydrationLog -Message "  Failed: $ProfileName - $($_.Exception.Message)" -Level Warning
        return New-HydrationResult -Name $ProfileName -Type 'MacOSDEPEnrollmentProfile' -Action 'Failed' -Status $_.Exception.Message
    }
}
