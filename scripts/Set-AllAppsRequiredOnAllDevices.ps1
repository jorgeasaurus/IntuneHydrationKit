#Requires -Version 7.0

<#
.SYNOPSIS
    Assigns all Intune apps as required on all devices.

.DESCRIPTION
    Queries Microsoft Intune mobile apps, preserves any existing assignments, and adds
    a Required assignment targeting All Devices when one does not already exist.
    Supports -WhatIf for dry-run validation.

.PARAMETER AppTypes
    Mobile app @odata.type values to include. Defaults to common deployable app types.

.EXAMPLE
    ./scripts/Set-AllAppsRequiredOnAllDevices.ps1 -WhatIf

.EXAMPLE
    ./scripts/Set-AllAppsRequiredOnAllDevices.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$AppTypes = @(
        '#microsoft.graph.win32LobApp',
        '#microsoft.graph.winGetApp',
        '#microsoft.graph.microsoftStoreForBusinessApp',
        '#microsoft.graph.officeSuiteApp',
        '#microsoft.graph.windowsMicrosoftEdgeApp',
        '#microsoft.graph.windowsUniversalAppX',
        '#microsoft.graph.iosStoreApp',
        '#microsoft.graph.iosLobApp',
        '#microsoft.graph.managedIOSStoreApp',
        '#microsoft.graph.androidStoreApp',
        '#microsoft.graph.androidLobApp',
        '#microsoft.graph.managedAndroidStoreApp',
        '#microsoft.graph.macOSLobApp',
        '#microsoft.graph.macOSDmgApp',
        '#microsoft.graph.macOSPkgApp'
    )
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'AssignmentHelpers.ps1')

function Get-MobileApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$IncludedTypes
    )

    $apps = [System.Collections.Generic.List[object]]::new()
    $uri = 'beta/deviceAppManagement/mobileApps'

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        foreach ($app in @($response.value)) {
            if ($app.'@odata.type' -in $IncludedTypes) {
                $apps.Add($app)
            }
        }

        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return @($apps)
}

function Get-MobileAppAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId
    )

    $response = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceAppManagement/mobileApps/$AppId/assignments" -ErrorAction Stop
    return @($response.value)
}

function Get-RequiredAssignmentSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MobileAppType,

        [Parameter()]
        [AllowNull()]
        [object[]]$ExistingAssignments
    )

    # Reuse settings from an existing required assignment if present
    $existingRequired = @($ExistingAssignments | Where-Object { $_.intent -eq 'required' } | Select-Object -First 1)
    if ($existingRequired.Count -gt 0 -and $null -ne $existingRequired[0].settings) {
        $settings = ConvertTo-PlainValue -InputObject $existingRequired[0].settings
        if ($settings -is [System.Collections.IDictionary]) {
            foreach ($readOnlyKey in @('id', 'lastModifiedDateTime')) {
                if ($settings.Contains($readOnlyKey)) {
                    $null = $settings.Remove($readOnlyKey)
                }
            }
        }

        return $settings
    }

    switch ($MobileAppType) {
        '#microsoft.graph.win32LobApp' {
            return @{
                '@odata.type'                = '#microsoft.graph.win32LobAppAssignmentSettings'
                notifications                = 'showAll'
                deliveryOptimizationPriority = 'notConfigured'
                installTimeSettings          = $null
                restartSettings              = $null
            }
        }
        default {
            return $null
        }
    }
}

function ConvertTo-WritableAssignmentSetting {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Settings
    )

    $writableSettings = ConvertTo-PlainValue -InputObject $Settings
    if ($writableSettings -is [System.Collections.IDictionary]) {
        foreach ($readOnlyKey in @('id', 'lastModifiedDateTime')) {
            if ($writableSettings.Contains($readOnlyKey)) {
                $null = $writableSettings.Remove($readOnlyKey)
            }
        }
    }

    return $writableSettings
}

function ConvertTo-MobileAppAssignmentPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Assignment
    )

    process {
        @{
            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
            intent        = [string]$Assignment.intent
            target        = ConvertTo-PlainValue -InputObject $Assignment.target
            settings      = ConvertTo-WritableAssignmentSetting -Settings $Assignment.settings
        }
    }
}

function Set-AppRequiredAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MobileAppType
    )

    $existingAssignments = Get-MobileAppAssignment -AppId $AppId

    # Skip if already has a Required assignment targeting All Devices
    $existingRequired = @(
        $existingAssignments | Where-Object {
            $_.intent -eq 'required' -and
            $_.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget'
        }
    )

    if ($existingRequired.Count -gt 0) {
        return [PSCustomObject]@{
            Name   = $AppName
            Type   = $MobileAppType
            Status = 'Skipped'
            Reason = 'Already required on All Devices'
        }
    }

    # Build the assignment list: preserve existing + add the new required assignment
    $assignmentPayload = [System.Collections.Generic.List[object]]::new()
    foreach ($assignment in $existingAssignments) {
        $assignmentPayload.Add((ConvertTo-MobileAppAssignmentPayload -Assignment $assignment))
    }

    $assignmentPayload.Add(@{
            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
            intent        = 'required'
            target        = @{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
            }
            settings      = Get-RequiredAssignmentSetting -MobileAppType $MobileAppType -ExistingAssignments $existingAssignments
        })

    if (-not $PSCmdlet.ShouldProcess($AppName, 'Assign as Required on All Devices')) {
        return [PSCustomObject]@{
            Name   = $AppName
            Type   = $MobileAppType
            Status = 'WhatIf'
            Reason = $null
        }
    }

    $bodyJson = @{
        mobileAppAssignments = @($assignmentPayload)
    } | ConvertTo-Json -Depth 30

    Invoke-MgGraphRequest -Method POST -Uri "beta/deviceAppManagement/mobileApps/$AppId/assign" -Body $bodyJson -ContentType 'application/json' -ErrorAction Stop | Out-Null

    return [PSCustomObject]@{
        Name   = $AppName
        Type   = $MobileAppType
        Status = 'Assigned'
        Reason = $null
    }
}

# --- Main ---

Connect-AssignmentGraph

$apps = Get-MobileApp -IncludedTypes $AppTypes
if ($apps.Count -eq 0) {
    Write-Warning 'No matching apps were found in Intune.'
    return
}

$results = foreach ($app in $apps) {
    try {
        Set-AppRequiredAssignment -AppId $app.id -AppName $app.displayName -MobileAppType $app.'@odata.type'
    } catch {
        [PSCustomObject]@{
            Name   = [string]$app.displayName
            Type   = [string]$app.'@odata.type'
            Status = 'Failed'
            Reason = $_.Exception.Message
        }
    }
}

$results
