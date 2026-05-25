function Test-HydrationNonEmptyArrayValue {
    <#
    .SYNOPSIS
        Checks whether a value is a non-empty array.
    .PARAMETER Value
        The value to evaluate.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    return $Value -is [array] -and $Value.Count -gt 0
}
