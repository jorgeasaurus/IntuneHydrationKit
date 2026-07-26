#Requires -Version 7.0

<#
.SYNOPSIS
    Shared helpers for the app assignment scripts.

.DESCRIPTION
    Dot-sourced by Set-AllAppsRequiredOnAllDevices.ps1 and
    Set-WindowsAppsAvailableToAllUsers.ps1.
#>

function Connect-AssignmentGraph {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RequiredScope = 'DeviceManagementApps.ReadWrite.All'
    )

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
