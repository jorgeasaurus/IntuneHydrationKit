function Show-HydrationTuiOptionPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [object[]]$Options
    )

    Clear-HydrationTuiScreen
    Show-HydrationTuiHeader
    Show-HydrationTuiPanel -Title $Title -Lines @(
        foreach ($option in $Options) {
            "{0}. {1}" -f $option.Number, $option.Label
        }
    )
}
