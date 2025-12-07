function Import-IntuneMobileApp {
    <#
    .SYNOPSIS
        Imports mobile apps from JSON templates
    .DESCRIPTION
        Reads JSON templates from Templates/MobileApps and creates mobile apps via Graph API.
    .PARAMETER TemplatePath
        Path to the mobile apps template directory (defaults to Templates/MobileApps)
    .PARAMETER RemoveExisting
        If specified, removes existing mobile apps that were created by Intune-Hydration-Kit
    .EXAMPLE
        Import-IntuneMobileApp
    .EXAMPLE
        Import-IntuneMobileApp -RemoveExisting
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [switch]$RemoveExisting
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "MobileApps"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "MobileApps template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-HydrationTemplates -Path $TemplatePath -Recurse -ResourceType "mobile app template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No mobile app templates found in: $TemplatePath"
        return @()
    }

    # Prefetch existing mobile apps (paged)
    $existingApps = @{}
    $listUri = "beta/deviceAppManagement/mobileApps"
    try {
        do {
            $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($app in $existingResponse.value) {
                $appName = $app.displayName
                if ($appName -and -not $existingApps.ContainsKey($appName)) {
                    $existingApps[$appName] = @{
                        Id = $app.id
                        Notes = $app.notes
                    }
                }
            }
            $listUri = $existingResponse.'@odata.nextLink'
        } while ($listUri)
    }
    catch {
        Write-Warning "Failed to list existing mobile apps: $($_.Exception.Message)"
    }

    $results = @()

    # Remove existing apps if requested
    if ($RemoveExisting) {
        foreach ($appName in $existingApps.Keys) {
            $appInfo = $existingApps[$appName]

            # Safety check: Only delete if created by this kit (has hydration marker in notes)
            if (-not (Test-HydrationKitObject -Description $appInfo.Notes -ObjectName $appName)) {
                Write-Verbose "Skipping '$appName' - not created by Intune-Hydration-Kit"
                continue
            }

            $deleteEndpoint = "beta/deviceAppManagement/mobileApps/$($appInfo.Id)"

            if ($PSCmdlet.ShouldProcess($appName, "Delete mobile app")) {
                try {
                    Invoke-MgGraphRequest -Method DELETE -Uri $deleteEndpoint -ErrorAction Stop
                    Write-HydrationLog -Message "  Deleted: $appName" -Level Info
                    $results += New-HydrationResult -Name $appName -Type 'MobileApp' -Action 'Deleted' -Status 'Success'
                }
                catch {
                    $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $appName - $errMessage" -Level Warning
                    $results += New-HydrationResult -Name $appName -Type 'MobileApp' -Action 'Failed' -Status "Delete failed: $errMessage"
                }
            }
            else {
                Write-HydrationLog -Message "  WouldDelete: $appName" -Level Info
                $results += New-HydrationResult -Name $appName -Type 'MobileApp' -Action 'WouldDelete' -Status 'DryRun'
            }
        }

        return $results
    }

    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $displayName = $template.displayName
            if (-not $displayName) {
                Write-Warning "Template missing displayName: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'MobileApp' -Action 'Failed' -Status 'Missing displayName'
                continue
            }

            if ($existingApps.ContainsKey($displayName)) {
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'MobileApp' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            $importBody = Copy-DeepObject -InputObject $template
            Remove-ReadOnlyGraphProperties -InputObject $importBody

            # Add hydration kit tag to notes field (mobile apps use notes instead of description for this)
            $existingNotes = if ($importBody.notes) { $importBody.notes } else { "" }
            $importBody.notes = if ($existingNotes) { "$existingNotes - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }

            $endpoint = "beta/deviceAppManagement/mobileApps"

            if ($PSCmdlet.ShouldProcess($displayName, "Create mobile app")) {
                $null = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                Write-HydrationLog -Message "  Created: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'MobileApp' -Action 'Created' -Status 'Success'
            }
            else {
                Write-HydrationLog -Message "  WouldCreate: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'MobileApp' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'MobileApp' -Action 'Failed' -Status $errMessage
        }
    }

    return $results
}
