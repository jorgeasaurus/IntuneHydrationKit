function Test-HydrationBatchStatusRetryable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Status,

        [Parameter(Mandatory)]
        [ValidateSet('POST', 'DELETE')]
        [string]$Operation
    )

    if ($Status -eq 429) {
        return $true
    }

    if ($Operation -eq 'DELETE' -and $Status -ge 500 -and $Status -lt 600) {
        return $true
    }

    return $false
}
