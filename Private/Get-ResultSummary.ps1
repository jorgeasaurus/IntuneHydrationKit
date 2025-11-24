function Get-ResultSummary {
    <#
    .SYNOPSIS
        Calculates summary statistics from hydration results
    .DESCRIPTION
        Internal helper function for aggregating result counts by action type
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [array]$Results = @()
    )

    # Single-pass iteration for better performance
    $summary = @{
        Created = 0
        Updated = 0
        Deleted = 0
        Skipped = 0
        WouldCreate = 0
        WouldUpdate = 0
        WouldDelete = 0
        Failed = 0
    }

    foreach ($result in $Results) {
        if ($result.Action -and $summary.ContainsKey($result.Action)) {
            $summary[$result.Action]++
        }
    }

    return $summary
}
