function Import-IntuneMobileApp {
    <#
    .SYNOPSIS
        Imports mobile apps from JSON templates
    .DESCRIPTION
        Reads JSON templates from Templates/MobileApps and creates mobile apps via Graph API.
    .PARAMETER TemplatePath
        Path to the mobile apps template directory (defaults to Templates/MobileApps)
    .PARAMETER RemoveExisting
        If specified, removes existing mobile apps that were created by Intune Hydration Kit
    .PARAMETER Platform
        Filter templates by platform. Valid values: Windows, macOS, All.
        Defaults to 'All' which imports all mobile app templates regardless of platform.
        Note: Mobile app templates are organized by Windows and macOS directories.
    .EXAMPLE
        Import-IntuneMobileApp
    .EXAMPLE
        Import-IntuneMobileApp -RemoveExisting
    .EXAMPLE
        Import-IntuneMobileApp -Platform Windows
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'All')]
        [string[]]$Platform = @('All'),

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

    $templateFiles = Get-FilteredTemplates -Path $TemplatePath -Platform $Platform -FilterMode 'Directory' -Recurse -ResourceType "mobile app template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No mobile app templates found in: $TemplatePath"
        return @()
    }

    # Prefetch existing mobile apps (paged)
    $existingApps = @{}
    $listUri = "beta/deviceAppManagement/mobileApps?`$select=id,displayName,notes"
    try {
        do {
            $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($app in $existingResponse.value) {
                $appName = $app.displayName
                if ($appName -and -not $existingApps.ContainsKey($appName)) {
                    $existingApps[$appName] = @{
                        Id    = $app.id
                        Notes = $app.notes
                    }
                }
            }
            $listUri = $existingResponse.'@odata.nextLink'
        } while ($listUri)
    } catch {
        Write-Warning "Failed to list existing mobile apps: $($_.Exception.Message)"
    }

    $results = @()

    # Remove existing apps if requested
    if ($RemoveExisting) {
        $appsToDelete = @()
        foreach ($appName in $existingApps.Keys) {
            $appInfo = $existingApps[$appName]

            if (-not (Test-HydrationKitObject -Description $appInfo.Notes -ObjectName $appName)) {
                Write-Verbose "Skipping '$appName' - not created by Intune Hydration Kit"
                continue
            }

            $appsToDelete += @{
                Name = $appName
                Id   = $appInfo.Id
            }
        }

        if ($appsToDelete.Count -eq 0) {
            Write-Verbose "No mobile apps found to delete"
            return $results
        }

        if ($WhatIfPreference) {
            foreach ($app in $appsToDelete) {
                Write-HydrationLog -Message "  WouldDelete: $($app.Name)" -Level Info
                $results += New-HydrationResult -Name $app.Name -Type 'MobileApp' -Action 'WouldDelete' -Status 'DryRun'
            }
            return $results
        }

        return Invoke-GraphBatchOperation -Items $appsToDelete -Operation 'DELETE' -BaseUrl '/deviceAppManagement/mobileApps' -ResultType 'MobileApp'
    }

    # Collect apps to create
    $appsToCreate = @()
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
                $results += New-HydrationResult -Name $displayName -Id $existingApps[$displayName].Id -Path $templateFile.FullName -Type 'MobileApp' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            $importBody = Copy-DeepObject -InputObject $template
            Remove-ReadOnlyGraphProperties -InputObject $importBody

            # Add hydration kit tag to notes field (mobile apps use notes instead of description for this)
            $existingNotes = if ($importBody.PSObject.Properties['notes']) { $importBody.notes } else { "" }
            $newNotes = if ($existingNotes) { "$existingNotes - Imported by Intune Hydration Kit" } else { "Imported by Intune Hydration Kit" }
            if ($importBody.PSObject.Properties['notes']) {
                $importBody.notes = $newNotes
            } else {
                $importBody | Add-Member -NotePropertyName 'notes' -NotePropertyValue $newNotes
            }

            # Store as JSON string to avoid serialization issues
            $appsToCreate += @{
                Name     = $displayName
                Path     = $templateFile.FullName
                BodyJson = ($importBody | ConvertTo-Json -Depth 100 -Compress)
            }
        } catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'MobileApp' -Action 'Failed' -Status $errMessage
        }
    }

    if ($WhatIfPreference) {
        foreach ($app in $appsToCreate) {
            Write-HydrationLog -Message "  WouldCreate: $($app.Name)" -Level Info
            $results += New-HydrationResult -Name $app.Name -Path $app.Path -Type 'MobileApp' -Action 'WouldCreate' -Status 'DryRun'
        }
        return $results
    }

    if ($appsToCreate.Count -gt 0) {
        $results += Invoke-GraphBatchOperation -Items $appsToCreate -Operation 'POST' -BaseUrl '/deviceAppManagement/mobileApps' -ResultType 'MobileApp'
    }

    return $results
}
