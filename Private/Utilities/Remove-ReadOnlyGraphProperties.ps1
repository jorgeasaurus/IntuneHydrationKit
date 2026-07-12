function Remove-ReadOnlyGraphProperties {
    <#
    .SYNOPSIS
        Removes read-only and system properties from a Graph API object before import
    .DESCRIPTION
        Internal helper function that removes common read-only properties that cannot be
        included when creating or updating resources via Microsoft Graph API.
        Accepts additional properties to remove for resource-specific cleanup.
    .PARAMETER InputObject
        The PSObject to remove properties from (modified in place)
    .PARAMETER AdditionalProperties
        Additional property names to remove beyond the core read-only set
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject]$InputObject,

        [Parameter()]
        [string[]]$AdditionalProperties = @()
    )

    # Core read-only properties common to most Graph resources
    $coreReadOnlyProperties = @(
        'id',
        'createdDateTime',
        'lastModifiedDateTime',
        'version',
        '@odata.context'
    )

    # Combine core properties with any additional ones
    $allPropertiesToRemove = $coreReadOnlyProperties + $AdditionalProperties
    $visitedNodes = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)

    function Test-ShouldRemoveProperty {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        if ($Name -in $allPropertiesToRemove) {
            return $true
        }

        if ($Name -like '#*') {
            return $true
        }

        if ($Name -match '@odata\.') {
            return $Name -ne '@odata.type' -and $Name -notlike '*@odata.bind'
        }

        return $false
    }

    function Test-IsScalarLikeNode {
        param(
            [Parameter()]
            [object]$Node
        )

        return (
            $Node -is [string] -or
            $Node -is [System.ValueType] -or
            $Node -is [System.Uri] -or
            $Node -is [System.Version]
        )
    }

    function Get-NoteProperties {
        param(
            [Parameter()]
            [object]$Node
        )

        if (-not $Node.PSObject -or -not $Node.PSObject.Properties) {
            return @()
        }

        return @($Node.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    }

    function Remove-PropertiesRecursively {
        param(
            [Parameter()]
            [object]$Node
        )

        if ($null -eq $Node -or (Test-IsScalarLikeNode -Node $Node)) {
            return
        }

        if (-not $visitedNodes.Add($Node)) {
            return
        }

        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($key in @($Node.Keys)) {
                if (Test-ShouldRemoveProperty -Name ([string]$key)) {
                    $Node.Remove($key)
                }
            }

            foreach ($key in @($Node.Keys)) {
                Remove-PropertiesRecursively -Node $Node[$key]
            }
            return
        }

        if ($Node -is [System.Collections.IEnumerable]) {
            foreach ($item in @($Node)) {
                Remove-PropertiesRecursively -Node $item
            }
            return
        }

        $noteProperties = Get-NoteProperties -Node $Node
        if ($noteProperties.Count -eq 0) {
            return
        }

        foreach ($property in $noteProperties) {
            if (Test-ShouldRemoveProperty -Name $property.Name) {
                $Node.PSObject.Properties.Remove($property.Name)
            }
        }

        foreach ($property in (Get-NoteProperties -Node $Node)) {
            Remove-PropertiesRecursively -Node $property.Value
        }
    }

    Remove-PropertiesRecursively -Node $InputObject
}
