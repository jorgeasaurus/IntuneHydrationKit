#Requires -Version 7.0

<#
.SYNOPSIS
    Assigns managed Windows OIB Settings Catalog policies to their intended built-in target.

.DESCRIPTION
    Finds Intune Hydration Kit-managed Windows Settings Catalog policies whose OIB names include a scope marker.
    Policies named `- U -` are assigned to All Users and policies named `- D -` are
    assigned to All Devices. Existing assignments are preserved in the assign action.
    A filtered target is treated as a conflict instead of an equivalent built-in target.

.EXAMPLE
    ./scripts/Set-WindowsOIBSettingsCatalogAssignments.ps1 -WhatIf

.EXAMPLE
    ./scripts/Set-WindowsOIBSettingsCatalogAssignments.ps1

.EXAMPLE
    ./scripts/Set-WindowsOIBSettingsCatalogAssignments.ps1 -PolicyId 'policy-id'

.EXAMPLE
    ./scripts/Set-WindowsOIBSettingsCatalogAssignments.ps1 -IncludeUnmanaged
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$PolicyId,

    [Parameter()]
    [switch]$IncludeUnmanaged
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'AssignmentHelpers.ps1')

function Get-WindowsOIBSettingsCatalogPolicy {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$PolicyId,

        [Parameter()]
        [switch]$IncludeUnmanaged
    )

    $policies = [System.Collections.Generic.List[object]]::new()
    $uri = 'beta/deviceManagement/configurationPolicies?$select=id,name,platforms'

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        foreach ($policy in @($response.value)) {
            $name = [string]$policy.name
            $isExplicitPolicy = $policy.id -in $PolicyId
            $isRequestedPolicy = $PolicyId.Count -eq 0 -or $isExplicitPolicy
            $scope = Get-OIBPolicyScope -PolicyName $name
            $isManagedPolicy = $name -match '^\[IHD\]\s*'
            if ($policy.platforms -eq 'windows10' -and $isRequestedPolicy -and $scope -and ($isManagedPolicy -or $IncludeUnmanaged -or $isExplicitPolicy)) {
                $policies.Add($policy)
            }
        }

        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return @($policies)
}

function Get-ConfigurationPolicyAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyId
    )

    $assignments = [System.Collections.Generic.List[object]]::new()
    $uri = "beta/deviceManagement/configurationPolicies/$PolicyId/assignments"

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        foreach ($assignment in @($response.value)) {
            $assignments.Add($assignment)
        }

        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return @($assignments)
}

function Get-OIBPolicyScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyName
    )

    $match = [regex]::Match($PolicyName, '^(?:\[IHD\]\s*)?Win - OIB - .+ - (?<Scope>[UD]) - ')
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups['Scope'].Value
}

function Get-OIBAssignmentTargetType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyName
    )

    switch (Get-OIBPolicyScope -PolicyName $PolicyName) {
        'U' {
            return '#microsoft.graph.allLicensedUsersAssignmentTarget'
        }
        'D' {
            return '#microsoft.graph.allDevicesAssignmentTarget'
        }
        default {
            throw "Policy '$PolicyName' does not contain an OIB user or device scope marker."
        }
    }
}

function Test-DirectConfigurationPolicyAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Assignment
    )

    $source = [string]$Assignment.source
    $sourceId = [string]$Assignment.sourceId
    return ([string]::IsNullOrWhiteSpace($source) -or $source -eq 'direct') -and [string]::IsNullOrWhiteSpace($sourceId)
}

function ConvertTo-ConfigurationPolicyAssignmentPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Assignment
    )

    process {
        return @{
            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicyAssignment'
            source        = 'direct'
            target        = ConvertTo-PlainValue -InputObject $Assignment.target
        }
    }
}

function Test-UnfilteredConfigurationPolicyAssignmentTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Assignment,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetType
    )

    $target = $Assignment.target
    if ($target.'@odata.type' -ne $TargetType) {
        return $false
    }

    $filterType = [string]$target.deviceAndAppManagementAssignmentFilterType
    $filterId = [string]$target.deviceAndAppManagementAssignmentFilterId
    return ([string]::IsNullOrWhiteSpace($filterType) -or $filterType -eq 'none') -and [string]::IsNullOrWhiteSpace($filterId)
}

function Set-OIBSettingsCatalogAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyName
    )

    $targetType = Get-OIBAssignmentTargetType -PolicyName $PolicyName
    $targetName = if ($targetType -eq '#microsoft.graph.allLicensedUsersAssignmentTarget') {
        'All Users'
    } else {
        'All Devices'
    }

    $existingAssignments = Get-ConfigurationPolicyAssignment -PolicyId $PolicyId
    $indirectAssignments = @($existingAssignments | Where-Object { -not (Test-DirectConfigurationPolicyAssignment -Assignment $_) })
    if ($indirectAssignments.Count -gt 0) {
        throw "Policy '$PolicyName' has an assignment owned by a policy set. Refusing to replay it as a direct assignment."
    }

    $matchingTargets = @($existingAssignments | Where-Object { $_.target.'@odata.type' -eq $targetType })
    $unfilteredTarget = @($matchingTargets | Where-Object { Test-UnfilteredConfigurationPolicyAssignmentTarget -Assignment $_ -TargetType $targetType })
    if ($unfilteredTarget.Count -gt 0) {
        return [PSCustomObject]@{
            Name   = $PolicyName
            Target = $targetName
            Status = 'Skipped'
            Reason = "Already assigned to $targetName"
        }
    }

    if ($matchingTargets.Count -gt 0) {
        throw "Policy '$PolicyName' has a filtered $targetName assignment. Refusing to add an unfiltered target."
    }

    if (-not $PSCmdlet.ShouldProcess($PolicyName, "Assign to $targetName")) {
        $status = if ($WhatIfPreference) { 'WhatIf' } else { 'Cancelled' }
        return [PSCustomObject]@{
            Name   = $PolicyName
            Target = $targetName
            Status = $status
            Reason = $null
        }
    }

    $assignmentPayload = [System.Collections.Generic.List[object]]::new()
    foreach ($assignment in $existingAssignments) {
        $assignmentPayload.Add((ConvertTo-ConfigurationPolicyAssignmentPayload -Assignment $assignment))
    }

    $assignmentPayload.Add(@{
            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicyAssignment'
            source        = 'direct'
            target        = @{
                '@odata.type' = $targetType
            }
        })

    $bodyJson = @{
        assignments = @($assignmentPayload)
    } | ConvertTo-Json -Depth 10

    Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/configurationPolicies/$PolicyId/assign" -Body $bodyJson -ContentType 'application/json' -ErrorAction Stop | Out-Null

    $verifiedAssignments = Get-ConfigurationPolicyAssignment -PolicyId $PolicyId
    $verifiedTarget = @($verifiedAssignments | Where-Object { Test-UnfilteredConfigurationPolicyAssignmentTarget -Assignment $_ -TargetType $targetType })
    if ($verifiedTarget.Count -eq 0) {
        throw "Policy '$PolicyName' did not retain the requested unfiltered $targetName assignment."
    }

    return [PSCustomObject]@{
        Name   = $PolicyName
        Target = $targetName
        Status = 'Assigned'
        Reason = $null
    }
}

function Invoke-OIBSettingsCatalogAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string[]]$PolicyId,

        [Parameter()]
        [switch]$IncludeUnmanaged
    )

    Connect-AssignmentGraph -RequiredScope 'DeviceManagementConfiguration.ReadWrite.All'

    $policies = Get-WindowsOIBSettingsCatalogPolicy -PolicyId $PolicyId -IncludeUnmanaged:$IncludeUnmanaged
    if ($policies.Count -eq 0) {
        Write-Warning 'No matching Windows OIB Settings Catalog policies were found.'
        return
    }

    foreach ($policy in $policies) {
        try {
            Set-OIBSettingsCatalogAssignment -PolicyId $policy.id -PolicyName $policy.name -WhatIf:$WhatIfPreference
        } catch {
            [PSCustomObject]@{
                Name   = [string]$policy.name
                Target = $null
                Status = 'Failed'
                Reason = $_.Exception.Message
            }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-OIBSettingsCatalogAssignment -PolicyId $PolicyId -IncludeUnmanaged:$IncludeUnmanaged -WhatIf:$WhatIfPreference
}
