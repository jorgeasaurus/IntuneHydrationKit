function Format-HydrationGraphAccessIssue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$AccessIssues = @()
    )

    $validAccessIssues = @($AccessIssues | Where-Object { $null -ne $_ })
    if ($validAccessIssues.Count -eq 0) {
        return @()
    }

    $workloadNames = @(
        $validAccessIssues |
            Sort-Object -Property Name -Unique |
            ForEach-Object { $_.Name }
    ) -join ', '

    return @(
        "Access denied for selected imports: $workloadNames."
        'Global Administrator account required for selected imports.'
    )
}
