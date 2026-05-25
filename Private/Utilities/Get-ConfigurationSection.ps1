function Get-ConfigurationSection {
    <#
    .SYNOPSIS
        Gets a named section from a configuration hashtable.
    .DESCRIPTION
        Returns an empty hashtable when the requested section does not exist or is null.
    .PARAMETER InputObject
        Source configuration hashtable.
    .PARAMETER Name
        Section name to retrieve.
    .OUTPUTS
        object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($InputObject.ContainsKey($Name) -and $null -ne $InputObject[$Name]) {
        return $InputObject[$Name]
    }

    return @{}
}
