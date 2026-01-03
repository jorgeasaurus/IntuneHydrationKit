<#
.SYNOPSIS
    Assigns all mobile apps in Intune as available to all users for testing.

.DESCRIPTION
    This script loops through all mobile apps in Microsoft Intune and assigns each one
    as "available" to all users. Useful for quickly testing app deployments.

.PARAMETER WhatIf
    Preview changes without making any assignments.

.PARAMETER AppTypes
    Filter to specific app types. Default includes common types.
    Examples: winGetApp, microsoftStoreForBusinessApp, win32LobApp

.EXAMPLE
    .\Set-MobileAppAssignments.ps1
    # Assigns all apps as available to all users

.EXAMPLE
    .\Set-MobileAppAssignments.ps1 -WhatIf
    # Preview what would be assigned without making changes

.EXAMPLE
    .\Set-MobileAppAssignments.ps1 -AppTypes @('winGetApp')
    # Only assign WinGet (Microsoft Store) apps

.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - DeviceManagementApps.ReadWrite.All
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string[]]$AppTypes = @(
        '#microsoft.graph.winGetApp',
        '#microsoft.graph.microsoftStoreForBusinessApp',
        '#microsoft.graph.win32LobApp',
        '#microsoft.graph.windowsMicrosoftEdgeApp',
        '#microsoft.graph.officeSuiteApp',
        '#microsoft.graph.macOSMicrosoftEdgeApp',
        '#microsoft.graph.macOSOfficeSuiteApp'
    )
)

#region Functions
function Connect-ToGraph {
    <#
    .SYNOPSIS
        Ensures connection to Microsoft Graph with required scopes
    #>
    $requiredScopes = @('DeviceManagementApps.ReadWrite.All')

    $context = Get-MgContext
    if (-not $context) {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome
    }
    else {
        # Check if we have the required scope
        $hasScope = $context.Scopes | Where-Object { $_ -like '*DeviceManagementApps*' }
        if (-not $hasScope) {
            Write-Host "Reconnecting with required scopes..." -ForegroundColor Yellow
            Disconnect-MgGraph | Out-Null
            Connect-MgGraph -Scopes $requiredScopes -NoWelcome
        }
    }
}

function Get-AllMobileApps {
    <#
    .SYNOPSIS
        Retrieves all mobile apps from Intune with pagination support
    #>
    [CmdletBinding()]
    param()

    $apps = @()
    $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $apps += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return $apps
}

function Get-AppAssignments {
    <#
    .SYNOPSIS
        Gets existing assignments for a mobile app
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId
    )

    $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/assignments"
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri
    return $response.value
}

function Set-AppAvailableToAllUsers {
    <#
    .SYNOPSIS
        Assigns an app as available to all users
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$AppName
    )

    # Check for existing "All Users" assignment
    $existingAssignments = Get-AppAssignments -AppId $AppId
    $hasAllUsersAssignment = $existingAssignments | Where-Object {
        $_.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget'
    }

    if ($hasAllUsersAssignment) {
        Write-Host "  [Skip] $AppName - Already assigned to All Users" -ForegroundColor DarkGray
        return @{
            Name = $AppName
            Status = 'Skipped'
            Reason = 'Already assigned'
        }
    }

    if ($PSCmdlet.ShouldProcess($AppName, "Assign as Available to All Users")) {
        $assignmentBody = @{
            mobileAppAssignments = @(
                @{
                    "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                    intent = "available"
                    target = @{
                        "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget"
                    }
                    settings = $null
                }
            )
        }

        try {
            $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/assign"
            Invoke-MgGraphRequest -Method POST -Uri $uri -Body $assignmentBody -ContentType "application/json" | Out-Null

            Write-Host "  [OK] $AppName" -ForegroundColor Green
            return @{
                Name = $AppName
                Status = 'Assigned'
                Reason = $null
            }
        }
        catch {
            Write-Host "  [Error] $AppName - $($_.Exception.Message)" -ForegroundColor Red
            return @{
                Name = $AppName
                Status = 'Failed'
                Reason = $_.Exception.Message
            }
        }
    }
    else {
        Write-Host "  [WhatIf] Would assign: $AppName" -ForegroundColor Yellow
        return @{
            Name = $AppName
            Status = 'WhatIf'
            Reason = $null
        }
    }
}
#endregion

#region Main
Write-Host "`n=== Mobile App Assignment Script ===" -ForegroundColor Cyan
Write-Host "This script assigns all mobile apps as 'Available' to All Users`n"

# Connect to Graph
Connect-ToGraph

# Get all mobile apps
Write-Host "Fetching mobile apps from Intune..." -ForegroundColor Cyan
$allApps = Get-AllMobileApps

# Filter to specified app types
$filteredApps = $allApps | Where-Object { $_.'@odata.type' -in $AppTypes }

Write-Host "Found $($filteredApps.Count) apps to process (filtered from $($allApps.Count) total)`n" -ForegroundColor Cyan

if ($filteredApps.Count -eq 0) {
    Write-Host "No apps found matching the specified types." -ForegroundColor Yellow
    exit 0
}

# Process each app
$results = @()
Write-Host "Processing assignments:" -ForegroundColor Cyan

foreach ($app in $filteredApps) {
    $result = Set-AppAvailableToAllUsers -AppId $app.id -AppName $app.displayName
    $results += [PSCustomObject]$result
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$assigned = ($results | Where-Object { $_.Status -eq 'Assigned' }).Count
$skipped = ($results | Where-Object { $_.Status -eq 'Skipped' }).Count
$failed = ($results | Where-Object { $_.Status -eq 'Failed' }).Count
$whatif = ($results | Where-Object { $_.Status -eq 'WhatIf' }).Count

Write-Host "Assigned: $assigned" -ForegroundColor Green
Write-Host "Skipped:  $skipped" -ForegroundColor DarkGray
if ($failed -gt 0) {
    Write-Host "Failed:   $failed" -ForegroundColor Red
}
if ($whatif -gt 0) {
    Write-Host "WhatIf:   $whatif" -ForegroundColor Yellow
}

# Return results for pipeline
$results
#endregion
