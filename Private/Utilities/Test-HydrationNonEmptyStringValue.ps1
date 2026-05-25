function Test-HydrationNonEmptyStringValue {
    <#
    .SYNOPSIS
        Checks whether a value is a non-empty string.
    .DESCRIPTION
        Treats null, empty, whitespace-only strings, and the literal string 'null' as empty.
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

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [array]) {
        return $false
    }

    $stringValue = $Value.ToString()
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
        return $false
    }

    return $stringValue -ne 'null'
}
