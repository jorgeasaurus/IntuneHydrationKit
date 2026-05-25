function Import-IntuneWinGetApp {
    <#
    .SYNOPSIS
        Imports WinGet-backed Win32 apps from bundled catalog or preset templates.
    .DESCRIPTION
        Creates Intune Win32 apps that wrap WinGet install and uninstall commands,
        publishes the generated .intunewin content, and tags created apps with both
        the hydration marker and WinGet ownership metadata so future deletes are safe.
    .PARAMETER TemplateId
        One or more specific bundled WinGet template IDs to import.
    .PARAMETER PresetId
        Optional preset ID to resolve from Templates/MobileApps/Windows/WinGet/Presets.
    .PARAMETER RemoveExisting
        Deletes matching WinGet hydration-owned Win32 apps instead of creating them.
    .PARAMETER WorkingDirectory
        Directory used to stage wrapper scripts, packages, and upload artifacts.
    .PARAMETER RemediationEnabled
        When enabled, creates or updates proactive remediation scripts for the selected
        WinGet app set. A system-scoped script is generated for machine apps and a
        user-scoped script is generated for user apps. No assignments are created.
    .EXAMPLE
        Import-IntuneWinGetApp -PresetId 'starter-pack'
    .EXAMPLE
        Import-IntuneWinGetApp -TemplateId 'google-chrome'
    .EXAMPLE
        Import-IntuneWinGetApp -RemoveExisting -PresetId 'starter-pack'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string[]]$TemplateId,

        [Parameter()]
        [string]$PresetId,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [string]$WorkingDirectory,

        [Parameter()]
        [switch]$RemediationEnabled
    )

    if (-not $WorkingDirectory) {
        $WorkingDirectory = Join-Path -Path (Get-Location).Path -ChildPath '.intunehydrationkit/winget-apps'
    }

    if (-not (Test-Path -Path $WorkingDirectory)) {
        $null = New-Item -Path $WorkingDirectory -ItemType Directory -Force -ErrorAction Stop
    }

    Write-Debug "Starting WinGet Win32 import. RemoveExisting=$($RemoveExisting.IsPresent), WorkingDirectory='$WorkingDirectory', PresetId='$PresetId', TemplateIdCount=$(@($TemplateId).Count)."

    $templates = @(Get-HydrationWinGetAppTemplates -TemplateId $TemplateId -PresetId $PresetId)
    if ($templates.Count -eq 0) {
        Write-Verbose 'No WinGet app templates found to process'
        return @()
    }

    $templateIds = (@($templates.templateId)) -join "', '"
    Write-Debug "Loaded $($templates.Count) WinGet template(s): '$templateIds'."

    $knownTemplateNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($template in $templates) {
        if (-not [string]::IsNullOrWhiteSpace($template.displayName)) {
            $templateDisplayName = [string]$template.displayName
            [void]$knownTemplateNames.Add((Get-HydrationMobileAppDisplayName -DisplayName $templateDisplayName))
        }
    }

    $existingApps = Get-ExistingWinGetApps -KnownTemplateNames $knownTemplateNames
    Write-Debug "Resolved $($existingApps.Items.Count) existing app(s) from Graph for WinGet ownership evaluation. LookupEntries=$($existingApps.Lookup.Count)."
    $results = @()

    $validTemplates = [System.Collections.Generic.List[psobject]]::new()
    foreach ($template in $templates) {
        if ([string]::IsNullOrWhiteSpace($template.packageIdentifier)) {
            $templateDisplayName = [string]$template.displayName
            $displayName = if ([string]::IsNullOrWhiteSpace($templateDisplayName)) {
                $template.templateId ?? 'UnknownTemplate'
            } else {
                Get-HydrationMobileAppDisplayName -DisplayName $templateDisplayName
            }
            Write-HydrationLog -Message "  Failed: $displayName - Missing or blank packageIdentifier for template '$($template.templateId)'" -Level Warning
            $results += New-HydrationResult -Name $displayName -Path $template.TemplatePath -Type 'WinGetWin32App' -Action 'Failed' -Status "Missing or blank packageIdentifier for template '$($template.templateId)'"
            continue
        }
        $validTemplates.Add($template)
    }
    $templates = $validTemplates

    if ($RemoveExisting) {
        $results += Remove-IntuneWinGetApps -ExistingApps $existingApps -KnownTemplateNames $knownTemplateNames -PSCmdlet $PSCmdlet -WhatIfPreference:$WhatIfPreference

        if ($RemediationEnabled.IsPresent) {
            $results += Sync-IntuneWinGetProactiveRemediation -Templates $templates -RemoveExisting -WhatIfEnabled:$WhatIfPreference
        }
        return $results
    }

    foreach ($template in $templates) {
        $templateDisplayName = [string]$template.displayName
        if ([string]::IsNullOrWhiteSpace($templateDisplayName)) {
            $results += New-HydrationResult -Name ($template.templateId ?? 'UnknownTemplate') -Path $template.TemplatePath -Type 'WinGetWin32App' -Action 'Failed' -Status 'Missing displayName'
            continue
        }

        $displayName = Get-HydrationMobileAppDisplayName -DisplayName $templateDisplayName
        if ($existingApps.Lookup.ContainsKey($displayName) -and $existingApps.Lookup[$displayName].IsOwned) {
            $matchedApp = $existingApps.Lookup[$displayName]
            Write-Debug "Create decision: skipping '$displayName' because matching WinGet-owned app '$($matchedApp.DisplayName)' already exists with AppId='$($matchedApp.Id)'."
            Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
            $results += New-HydrationResult -Name $displayName -Id $matchedApp.Id -Path $template.TemplatePath -Type 'WinGetWin32App' -Action 'Skipped' -Status 'Already exists'
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create WinGet Win32 app')) {
            if ($WhatIfPreference) {
                Write-Debug "Create decision: WhatIf prevented creation for '$displayName'."
                $results += Add-HydrationDryRunResult -Action 'WouldCreate' -Name $displayName -Path $template.TemplatePath -Type 'WinGetWin32App'
            }

            continue
        }

        $importParams = @{
            Template         = $template
            DisplayName      = $displayName
            WorkingDirectory = $WorkingDirectory
        }
        $results += Invoke-IntuneWinGetAppTemplate @importParams
    }

    if ($RemediationEnabled.IsPresent) {
        $results += Sync-IntuneWinGetProactiveRemediation -Templates $templates -WhatIfEnabled:$WhatIfPreference
    }

    return $results
}
