#Requires -Version 7.0

<#
.SYNOPSIS
    Assigns Intune Windows apps as available to all users.

.DESCRIPTION
    Queries Microsoft Intune mobile apps, filters to Windows app types, preserves any
    existing assignments, and adds an Available assignment for All Users when one does
    not already exist. This is intended as a development helper for quickly enabling
    user-available Windows apps in a test tenant.

.PARAMETER WindowsAppTypes
    Windows mobile app @odata.type values to include.

.EXAMPLE
    ./scripts/Set-WindowsAppsAvailableToAllUsers.ps1

.EXAMPLE
    ./scripts/Set-WindowsAppsAvailableToAllUsers.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$WindowsAppTypes = @(
        '#microsoft.graph.win32LobApp',
        '#microsoft.graph.winGetApp',
        '#microsoft.graph.microsoftStoreForBusinessApp',
        '#microsoft.graph.officeSuiteApp',
        '#microsoft.graph.windowsMicrosoftEdgeApp',
        '#microsoft.graph.windowsUniversalAppX'
    )
)

function Connect-AssignmentGraph {
    [CmdletBinding()]
    param()

    $requiredScope = 'DeviceManagementApps.ReadWrite.All'
    $context = Get-MgContext
    if (-not $context) {
        Connect-MgGraph -Scopes $requiredScope -NoWelcome | Out-Null
        return
    }

    if ($context.Scopes -notcontains $requiredScope) {
        Disconnect-MgGraph | Out-Null
        Connect-MgGraph -Scopes $requiredScope -NoWelcome | Out-Null
    }
}

function ConvertTo-PlainValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter()]
        [System.Collections.Generic.HashSet[object]]$Seen = [System.Collections.Generic.HashSet[object]]::new()
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $type = $InputObject.GetType()
    if ($type.IsValueType -or $InputObject -is [string]) {
        return $InputObject
    }

    if ($Seen.Contains($InputObject)) {
        return $null
    }
    $null = $Seen.Add($InputObject)

    try {
        if ($InputObject -is [System.Collections.IDictionary]) {
            $hash = @{}
            foreach ($key in $InputObject.Keys) {
                $hash[$key] = ConvertTo-PlainValue -InputObject $InputObject[$key] -Seen $Seen
            }
            return $hash
        }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = @{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $hash[$prop.Name] = ConvertTo-PlainValue -InputObject $prop.Value -Seen $Seen
            }
            return $hash
        }

        if ($InputObject -is [System.Collections.IEnumerable]) {
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $InputObject) {
                $list.Add((ConvertTo-PlainValue -InputObject $item -Seen $Seen))
            }
            return [object[]]$list.ToArray()
        }

        return $InputObject
    } finally {
        $null = $Seen.Remove($InputObject)
    }
}

function Get-WindowsMobileApp {
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

function Get-AvailableAssignmentSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MobileAppType,

        [Parameter()]
        [AllowNull()]
        [object]$ExistingAssignments
    )

    $availableAssignment = @($ExistingAssignments | Where-Object { $_.intent -eq 'available' } | Select-Object -First 1)
    if ($availableAssignment.Count -gt 0 -and $null -ne $availableAssignment[0].settings) {
        $settings = ConvertTo-PlainValue -InputObject $availableAssignment[0].settings
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

function Set-MobileAppAvailability {
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
    $allUsersAssignment = @(
        $existingAssignments | Where-Object {
            $_.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget'
        }
    )

    if ($allUsersAssignment.Count -gt 0) {
        return [PSCustomObject]@{
            Name   = $AppName
            Type   = $MobileAppType
            Status = 'Skipped'
            Reason = 'Already has an All Users assignment'
        }
    }

    $assignmentPayload = [System.Collections.Generic.List[object]]::new()
    foreach ($assignment in $existingAssignments) {
        $assignmentPayload.Add((ConvertTo-MobileAppAssignmentPayload -Assignment $assignment))
    }

    $assignmentPayload.Add(@{
            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
            intent        = 'available'
            target        = @{
                '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
            }
            settings      = Get-AvailableAssignmentSetting -MobileAppType $MobileAppType -ExistingAssignments $existingAssignments
        })

    if (-not $PSCmdlet.ShouldProcess($AppName, 'Assign as Available to All Users')) {
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

Connect-AssignmentGraph

$windowsApps = Get-WindowsMobileApp -IncludedTypes $WindowsAppTypes
if ($windowsApps.Count -eq 0) {
    Write-Warning 'No Windows apps were found in Intune.'
    return
}

$results = foreach ($app in $windowsApps) {
    try {
        Set-MobileAppAvailability -AppId $app.id -AppName $app.displayName -MobileAppType $app.'@odata.type'
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
