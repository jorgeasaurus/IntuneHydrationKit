function Copy-DeepObject {
    <#
    .SYNOPSIS
        Creates a deep copy of a PowerShell object
    .DESCRIPTION
        Internal helper function that creates a complete deep clone of an object
        using PowerShell serialization. This ensures nested objects and collections
        are fully copied rather than referenced.
    .PARAMETER InputObject
        The object to deep copy
    .EXAMPLE
        $copy = Copy-DeepObject -InputObject $originalObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    [Management.Automation.PSSerializer]::Deserialize(
        [Management.Automation.PSSerializer]::Serialize($InputObject)
    )
}
