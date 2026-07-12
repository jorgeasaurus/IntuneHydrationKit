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
    .PARAMETER TemplateId
        Optional mobile app template file names to include, without the .json extension.
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
        [string[]]$TemplateId,

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

    $templateFiles = @(
        Get-FilteredTemplates -Path $TemplatePath -Platform $Platform -FilterMode 'Directory' -Recurse -ResourceType "mobile app template" |
            Where-Object { -not (Test-IsWinGetTemplateFile -TemplateFile $_) }
    )

    $requestedTemplateIdDisplay = $null
    if ($TemplateId) {
        $requestedTemplateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $requestedTemplateIdValues = [System.Collections.Generic.List[string]]::new()
        foreach ($currentTemplateId in @($TemplateId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $trimmedTemplateId = ([string]$currentTemplateId).Trim()
            $requestedTemplateIdValues.Add($trimmedTemplateId)
            [void]$requestedTemplateIds.Add($trimmedTemplateId)
            [void]$requestedTemplateIds.Add(($trimmedTemplateId -replace '[^a-zA-Z0-9]', ''))
        }
        $requestedTemplateIdDisplay = $requestedTemplateIdValues -join ', '

        if ($requestedTemplateIds.Count -gt 0) {
            $templateFiles = @(
                $templateFiles |
                    Where-Object {
                        $requestedTemplateIds.Contains($_.BaseName) -or
                        $requestedTemplateIds.Contains(($_.BaseName -replace '[^a-zA-Z0-9]', ''))
                    }
            )
        }
    }

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($requestedTemplateIdDisplay)) {
            Write-Warning "No mobile app templates matched TemplateId value(s): $requestedTemplateIdDisplay"
            return @()
        }

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
                if ($appName) {
                    $isTagged = Test-HydrationKitObject -Notes $app.notes
                    if (-not $existingApps.ContainsKey($appName)) {
                        $existingApps[$appName] = @{
                            Id       = $app.id
                            Notes    = $app.notes
                            IsTagged = $isTagged
                        }
                    } elseif ($isTagged -and -not $existingApps[$appName].IsTagged) {
                        # Prefer the tagged (kit-created) version
                        $existingApps[$appName] = @{
                            Id       = $app.id
                            Notes    = $app.notes
                            IsTagged = $true
                        }
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
        $knownTemplateNames = Get-MobileAppTemplateNameSet -TemplateFiles $templateFiles

        $appsToDelete = @()
        foreach ($appName in $existingApps.Keys) {
            $appInfo = $existingApps[$appName]

            $deleteDecision = Resolve-HydrationMarkedDeleteCandidate `
                -Name $appName `
                -Notes $appInfo.Notes `
                -KnownTemplateNames $knownTemplateNames `
                -FullObjectUri "beta/deviceAppManagement/mobileApps/$($appInfo.Id)" `
                -MobileAppName
            if (-not $deleteDecision.IsMatch) {
                Write-Verbose "Skipping '$appName' - $($deleteDecision.Message)"
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

        if (-not $PSCmdlet.ShouldProcess("$($appsToDelete.Count) mobile app(s)", "Delete")) {
            if ($WhatIfPreference) {
                foreach ($app in $appsToDelete) {
                    Write-HydrationLog -Message "  WouldDelete: $($app.Name)" -Level Info
                    $results += New-HydrationResult -Name $app.Name -Type 'MobileApp' -Action 'WouldDelete' -Status 'DryRun'
                }
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
            if (-not $template.displayName) {
                Write-Warning "Template missing displayName: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'MobileApp' -Action 'Failed' -Status 'Missing displayName'
                continue
            }

            $originalName = $template.displayName
            $displayName = Get-HydrationMobileAppDisplayName -DisplayName $originalName
            $matchedName = Get-HydrationMobileAppExistingMatch -ExistingApps $existingApps -DisplayName $originalName
            if ($matchedName) {
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Id $existingApps[$matchedName].Id -Path $templateFile.FullName -Type 'MobileApp' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            $importBody = Copy-DeepObject -InputObject $template
            Remove-ReadOnlyGraphProperties -InputObject $importBody

            # Apply import prefix to body
            if ($importBody.displayName) { $importBody.displayName = $displayName }

            # Add hydration kit tag to notes field (mobile apps use notes instead of description for this)
            $newNotes = New-HydrationDescription -ExistingText $(if ($importBody.PSObject.Properties['notes']) { $importBody.notes } else { '' })
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

    if (-not $PSCmdlet.ShouldProcess("$($appsToCreate.Count) mobile app(s)", "Create")) {
        if ($WhatIfPreference) {
            foreach ($app in $appsToCreate) {
                Write-HydrationLog -Message "  WouldCreate: $($app.Name)" -Level Info
                $results += New-HydrationResult -Name $app.Name -Path $app.Path -Type 'MobileApp' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        return $results
    }

    if ($appsToCreate.Count -gt 0) {
        $results += Invoke-GraphBatchOperation -Items $appsToCreate -Operation 'POST' -BaseUrl '/deviceAppManagement/mobileApps' -ResultType 'MobileApp'
    }

    return $results
}
