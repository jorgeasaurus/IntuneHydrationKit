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
        [switch]$Force,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [switch]$TestMode
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Notifications"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Notification template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File -Recurse

    # Test mode - only process first template
    if ($TestMode -and $templateFiles.Count -gt 0) {
        $templateFiles = $templateFiles | Select-Object -First 1
        Write-Host "Test mode: Processing only first template: $($templateFiles.Name)" -InformationAction Continue
    }

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No notification templates found in: $TemplatePath"
        return @()
    }

    $results = @()

    # Prefetch existing templates
    $existingByName = @{}
    try {
        $listUri = "beta/deviceManagement/notificationMessageTemplates"
        do {
            $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($tmpl in $existingResponse.value) {
                if ($tmpl.displayName -and -not $existingByName.ContainsKey($tmpl.displayName)) {
                    $existingByName[$tmpl.displayName] = $tmpl.id
                }
            }
            $listUri = $existingResponse.'@odata.nextLink'
        } while ($listUri)
    }
    catch {
        $existingByName = @{}
    }

    # Remove existing notification templates if requested - ONLY templates that match our files
    if ($RemoveExisting) {
        # Get template names to know what we manage
        $managedNames = @()
        foreach ($templateFile in $templateFiles) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json
            if ($template.displayName) {
                $managedNames += $template.displayName
            }
        }

        # Only delete templates that match our files
        $templatesToRemove = $existingByName.Keys | Where-Object { $_ -in $managedNames }

        if ($templatesToRemove.Count -gt 0) {
            Write-Host "Removing $($templatesToRemove.Count) managed notification templates..." -InformationAction Continue

            foreach ($templateName in $templatesToRemove) {
                $templateId = $existingByName[$templateName]

                if ($PSCmdlet.ShouldProcess($templateName, "Delete notification template")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/notificationMessageTemplates/$templateId" -ErrorAction Stop
                        Write-Host "Deleted notification template: $templateName (ID: $templateId)" -InformationAction Continue
                        $results += New-HydrationResult -Name $templateName -Type 'NotificationTemplate' -Action 'Deleted' -Status 'Success'
                    }
                    catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-Warning "Failed to delete notification template '$templateName': $errMessage"
                        $results += New-HydrationResult -Name $templateName -Type 'NotificationTemplate' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                }
                else {
                    $results += New-HydrationResult -Name $templateName -Type 'NotificationTemplate' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        }
        else {
            Write-Host "No managed notification templates found to delete" -InformationAction Continue
        }

        # RemoveExisting mode - only delete, don't create
        $summary = Get-ResultSummary -Results $results
        Write-Host "Notification template removal complete: $($summary.Deleted) deleted, $($summary.Failed) failed" -InformationAction Continue
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
                Write-Host "  Skipped: $displayName (already exists)" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            # Split template into main body and localized messages
            $localizedMessages = @()
            if ($template.localizedMessages) {
                $localizedMessages = $template.localizedMessages
                $template.PSObject.Properties.Remove('localizedMessages') | Out-Null
            }

            $importBody = $template | ConvertTo-Json -Depth 50 | ConvertFrom-Json

            if ($PSCmdlet.ShouldProcess($displayName, "Create notification template")) {
                $newTemplate = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/notificationMessageTemplates" -Body ($importBody | ConvertTo-Json -Depth 50) -ContentType "application/json" -ErrorAction Stop
                Write-Host "  Created: $displayName" -InformationAction Continue

                # Create localized messages if present
                foreach ($loc in $localizedMessages) {
                    try {
                        $locBody = $loc | ConvertTo-Json -Depth 20
                        Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/notificationMessageTemplates/$($newTemplate.id)/localizedNotificationMessages" -Body $locBody -ContentType "application/json" -ErrorAction Stop
                        Write-Host "  Added localized message ($($loc.locale))" -InformationAction Continue
                    }
                    catch {
                        Write-Warning "  Failed to add localized message ($($loc.locale)): $($_.Exception.Message)"
                    }
                }

                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-Warning "Failed to import notification template from $($templateFile.FullName): $errMessage"
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Failed' -Status $errMessage
        }
    }

    $summary = Get-ResultSummary -Results $results

    Write-Host "Notification template import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}