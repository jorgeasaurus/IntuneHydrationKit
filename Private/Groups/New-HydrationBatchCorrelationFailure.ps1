function New-HydrationBatchCorrelationFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ResponseState,

        [Parameter(Mandatory)]
        [string]$ResultTypeName,

        [Parameter(Mandatory)]
        [string]$StatusPrefix
    )

    $correlationResults = @()

    foreach ($unmatchedResponse in $ResponseState.Unmatched) {
        $name = "Unknown item (batch id $($unmatchedResponse.Response.id))"
        Write-Warning "  Failed: $name - Unmatched batch response"
        $correlationResults += New-HydrationResult -Type $ResultTypeName -Name $name -Action 'Failed' -Status "$StatusPrefix failed: Unmatched batch response id='$($unmatchedResponse.Response.id)'"
    }

    return $correlationResults
}
