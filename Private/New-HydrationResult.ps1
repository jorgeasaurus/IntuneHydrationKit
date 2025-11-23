function New-HydrationResult {
    <#
    .SYNOPSIS
        Creates a standardized result object for hydration operations
    .DESCRIPTION
        Internal helper function for creating consistent result objects across all hydration operations
    #>
    param(
        [string]$Name,
        [string]$Path,
        [string]$Type,
        [string]$Action,
        [Alias('Details')]
        [string]$Status,
        [string]$Id,
        [string]$Platform,
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
