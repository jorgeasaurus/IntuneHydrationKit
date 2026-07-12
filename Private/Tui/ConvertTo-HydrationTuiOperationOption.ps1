function ConvertTo-HydrationTuiOperationOption {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object]$Option
    )

    return $Option.Options
}
