function Test-HydrationTuiCancelValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return $false
    }

    return $Value.Trim() -in @('q', 'quit', 'cancel', 'exit')
}
