function Get-ResultSummary {
    <#
    .SYNOPSIS
        Calculates summary statistics from hydration results
    .DESCRIPTION
        Internal helper function for aggregating result counts by action type
    #>
    param([array]$Results)
    @{
        Created = ($Results | Where-Object { $_.Action -eq 'Created' }).Count
        Updated = ($Results | Where-Object { $_.Action -eq 'Updated' }).Count
        Deleted = ($Results | Where-Object { $_.Action -eq 'Deleted' }).Count
        Skipped = ($Results | Where-Object { $_.Action -eq 'Skipped' }).Count
        WouldCreate = ($Results | Where-Object { $_.Action -eq 'WouldCreate' }).Count
        WouldUpdate = ($Results | Where-Object { $_.Action -eq 'WouldUpdate' }).Count
        WouldDelete = ($Results | Where-Object { $_.Action -eq 'WouldDelete' }).Count
        Failed = ($Results | Where-Object { $_.Action -eq 'Failed' }).Count
    }
}
