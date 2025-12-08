function Import-IntuneNotificationTemplate {
    <#
    .SYNOPSIS
        Imports notification message templates from JSON templates
    .DESCRIPTION
        Reads templates from Templates/Notifications and creates notificationMessageTemplates with localized messages.
    .PARAMETER TemplatePath
        Path to the notifications template directory (defaults to Templates/Notifications)
    .EXAMPLE
        Import-IntuneNotificationTemplate
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [switch]$RemoveExisting
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Notifications"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Notification template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-HydrationTemplates -Path $TemplatePath -Recurse -ResourceType "notification template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No notification templates found in: $TemplatePath"
        return @()
    }

    $results = @()

    # Prefetch existing templates with descriptions for safety checks
    $existingTemplates = @{}
    try {
        $listUri = "beta/deviceManagement/notificationMessageTemplates"
        do {
            $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($tmpl in $existingResponse.value) {
                if ($tmpl.displayName -and -not $existingTemplates.ContainsKey($tmpl.displayName)) {
                    $existingTemplates[$tmpl.displayName] = @{
                        Id = $tmpl.id
                        Description = $tmpl.description
                    }
                }
            }
            $listUri = $existingResponse.'@odata.nextLink'
        } while ($listUri)
    }
    catch {
        $existingTemplates = @{}
    }

    # Build a simple name->id lookup for backwards compatibility in the import section
    $existingByName = @{}
    foreach ($key in $existingTemplates.Keys) {
        $existingByName[$key] = $existingTemplates[$key].Id
    }

    # Build list of template names from our JSON files for name-based matching
    $templateNames = @{}
    foreach ($templateFile in $templateFiles) {
        try {
            $templateContent = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            if ($templateContent.displayName) {
                $templateNames[$templateContent.displayName] = $true
            }
        }
        catch {
            Write-Verbose "Could not read template file: $($templateFile.FullName)"
        }
    }

    # Remove existing notification templates if requested
    # SAFETY: Only delete templates whose names match our template files
    # Note: Notification templates don't support description field, so we match by name
    if ($RemoveExisting) {
        foreach ($templateName in $existingTemplates.Keys) {
            $templateInfo = $existingTemplates[$templateName]

            # Safety check: Only delete if the name matches one of our template files
            if (-not $templateNames.ContainsKey($templateName)) {
                Write-Verbose "Skipping '$templateName' - not in hydration kit templates"
                continue
            }

            if ($PSCmdlet.ShouldProcess($templateName, "Delete notification template")) {
                try {
                    Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/notificationMessageTemplates/$($templateInfo.Id)" -ErrorAction Stop
                    Write-HydrationLog -Message "  Deleted: $templateName" -Level Info
                    $results += New-HydrationResult -Name $templateName -Type 'NotificationTemplate' -Action 'Deleted' -Status 'Success'
                }
                catch {
                    $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $templateName - $errMessage" -Level Warning
                    $results += New-HydrationResult -Name $templateName -Type 'NotificationTemplate' -Action 'Failed' -Status "Delete failed: $errMessage"
                }
            }
            else {
                Write-HydrationLog -Message "  WouldDelete: $templateName" -Level Info
                $results += New-HydrationResult -Name $templateName -Type 'NotificationTemplate' -Action 'WouldDelete' -Status 'DryRun'
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
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Failed' -Status 'Missing displayName'
                continue
            }

            if ($existingByName.ContainsKey($displayName)) {
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            # Split template into main body and localized messages
            $localizedMessages = @()
            if ($template.localizedMessages) {
                $localizedMessages = $template.localizedMessages
                $template.PSObject.Properties.Remove('localizedMessages') | Out-Null
            }

            $importBody = Copy-DeepObject -InputObject $template

            if ($PSCmdlet.ShouldProcess($displayName, "Create notification template")) {
                $newTemplate = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/notificationMessageTemplates" -Body ($importBody | ConvertTo-Json -Depth 50) -ContentType "application/json" -ErrorAction Stop
                Write-HydrationLog -Message "  Created: $displayName" -Level Info

                # Create localized messages if present
                foreach ($loc in $localizedMessages) {
                    try {
                        $locBody = $loc | ConvertTo-Json -Depth 20
                        Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/notificationMessageTemplates/$($newTemplate.id)/localizedNotificationMessages" -Body $locBody -ContentType "application/json" -ErrorAction Stop
                    }
                    catch {
                        Write-HydrationLog -Message "  Failed to add localized message ($($loc.locale)): $($_.Exception.Message)" -Level Warning
                    }
                }

                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Created' -Status 'Success'
            }
            else {
                Write-HydrationLog -Message "  WouldCreate: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Failed' -Status $errMessage
        }
    }

    return $results
}