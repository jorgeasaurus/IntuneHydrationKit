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

    foreach ($prop in $allPropertiesToRemove) {
        if ($InputObject.PSObject.Properties[$prop]) {
            $InputObject.PSObject.Properties.Remove($prop)
        }
    }
}
