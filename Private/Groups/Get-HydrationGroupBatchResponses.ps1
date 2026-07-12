function Get-HydrationGroupBatchResponses {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$BatchResponse
    )

    if ($BatchResponse -and $BatchResponse.responses) {
        return @($BatchResponse.responses)
    }

    return @()
}
