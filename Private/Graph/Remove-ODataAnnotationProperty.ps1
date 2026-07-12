function Remove-ODataAnnotationProperty {
    <#
    .SYNOPSIS
        Recursively removes OData annotation properties from an object graph
    .DESCRIPTION
        Walks a PSCustomObject/array structure (as produced by ConvertFrom-Json)
        and removes every property whose name contains '@odata.' except names
        exactly equal to '@odata.type', which Graph create endpoints require
        for polymorphic types.

        This handles both plain annotations (e.g. '@odata.context') and
        prefixed annotations (e.g. 'authenticationStrength@odata.context')
        that regex-based cleanup of serialized JSON misses.
    .PARAMETER InputObject
        The object graph to clean. Modified in place; also returned for convenience.
    .EXAMPLE
        $policy = Get-Content policy.json -Raw | ConvertFrom-Json
        Remove-ODataAnnotationProperty -InputObject $policy
    .OUTPUTS
        System.Object. The cleaned input object.
    .NOTES
        Internal helper. PSCustomObjects are mutated in place.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        foreach ($item in $InputObject) {
            $null = Remove-ODataAnnotationProperty -InputObject $item
        }
        return $InputObject
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $annotationNames = @(
            $InputObject.PSObject.Properties |
                Where-Object { $_.Name -like '*@odata.*' -and $_.Name -ne '@odata.type' } |
                ForEach-Object { $_.Name }
        )
        foreach ($name in $annotationNames) {
            $InputObject.PSObject.Properties.Remove($name)
        }
        foreach ($property in $InputObject.PSObject.Properties) {
            $null = Remove-ODataAnnotationProperty -InputObject $property.Value
        }
    }

    return $InputObject
}
