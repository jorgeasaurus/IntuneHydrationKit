function Resolve-HydrationBatchResponse {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [array]$BatchEntries,

        [Parameter()]
        [AllowEmptyCollection()]
        [array]$Responses = @()
    )

    $entryById = @{}
    foreach ($entry in $BatchEntries) {
        $entryById[[string]$entry.Id] = $entry
    }

    $seenRequestIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $matchedResponses = @()
    $unmatchedResponses = @()

    foreach ($response in @($Responses | Where-Object { $null -ne $_ })) {
        $requestId = [string]$response.id
        if (-not $entryById.ContainsKey($requestId)) {
            $unmatchedResponses += [pscustomobject]@{
                Response = $response
                Request  = $null
                Index    = $null
                Item     = $null
                Entry    = $null
            }
            continue
        }

        $entry = $entryById[$requestId]
        $seenRequestIds.Add($requestId) | Out-Null
        $matchedResponses += [pscustomobject]@{
            Response = $response
            Request  = $entry.Request
            Index    = $entry.Index
            Item     = $entry.Item
            Entry    = $entry
        }
    }

    $missingEntries = @()
    foreach ($entry in $BatchEntries) {
        $entryId = [string]$entry.Id
        if ($seenRequestIds.Contains($entryId)) {
            continue
        }

        $missingEntries += [pscustomobject]@{
            Request = $entry.Request
            Index   = $entry.Index
            Item    = $entry.Item
            Entry   = $entry
        }
    }

    return [pscustomobject]@{
        Matched   = $matchedResponses
        Missing   = $missingEntries
        Unmatched = $unmatchedResponses
    }
}
