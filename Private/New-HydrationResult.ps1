function New-HydrationResult {
    <#
    .SYNOPSIS
        Creates a standardized result object for hydration operations
    .DESCRIPTION
        Internal helper function for creating consistent result objects across all hydration operations
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [string]$Type,

        [Parameter()]
        [string]$Action,

        [Parameter()]
        [Alias('Details')]
        [string]$Status,

        [Parameter()]
        [string]$Id,

        [Parameter()]
        [string]$Platform,

        [Parameter()]
        [string]$State
    )
    $result = [PSCustomObject]@{
        Name = $Name
        Action = $Action
        Status = $Status
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    if ($Path) { $result | Add-Member -NotePropertyName 'Path' -NotePropertyValue $Path }
    if ($Type) { $result | Add-Member -NotePropertyName 'Type' -NotePropertyValue $Type }
    if ($Id) { $result | Add-Member -NotePropertyName 'Id' -NotePropertyValue $Id }
    if ($Platform) { $result | Add-Member -NotePropertyName 'Platform' -NotePropertyValue $Platform }
    if ($State) { $result | Add-Member -NotePropertyName 'State' -NotePropertyValue $State }
    return $result
}
