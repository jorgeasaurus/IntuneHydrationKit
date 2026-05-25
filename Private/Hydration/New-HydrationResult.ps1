function New-HydrationResult {
    <#
    .SYNOPSIS
        Creates a standardized result object for hydration operations
    .DESCRIPTION
        Internal helper function for creating consistent result objects across all hydration operations
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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

    $resultProperties = [ordered]@{
        Name      = $Name
        Action    = $Action
        Status    = $Status
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    $optionalProperties = [ordered]@{
        Path     = $Path
        Type     = $Type
        Id       = $Id
        Platform = $Platform
        State    = $State
    }

    foreach ($propertyName in $optionalProperties.Keys) {
        if (-not [string]::IsNullOrWhiteSpace($optionalProperties[$propertyName])) {
            $resultProperties[$propertyName] = $optionalProperties[$propertyName]
        }
    }

    return [PSCustomObject]$resultProperties
}
