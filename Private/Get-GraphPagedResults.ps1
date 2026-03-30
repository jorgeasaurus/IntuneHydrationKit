function Get-GraphPagedResults {
    <#
    .SYNOPSIS
        Fetches all pages of a Graph API paginated response
    .DESCRIPTION
        Handles the @odata.nextLink pagination pattern used by Microsoft Graph API.
        Can either accumulate all results and return them, or invoke a scriptblock
        per page for streaming/processing scenarios.
    .PARAMETER Uri
        The initial Graph API URI (relative, e.g., "beta/deviceManagement/configurationPolicies")
    .PARAMETER Headers
        Optional headers to include in the request
    .PARAMETER ProcessItems
        Optional scriptblock invoked with each page's .value array. When provided,
        items are NOT accumulated — the caller handles them in the scriptblock.
    .EXAMPLE
        # Accumulate all results
        $allPolicies = Get-GraphPagedResults -Uri "beta/deviceManagement/configurationPolicies"
    .EXAMPLE
        # Process each page (streaming)
        Get-GraphPagedResults -Uri "beta/groups" -ProcessItems { param($items) $items | ForEach-Object { ... } }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter()]
        [scriptblock]$ProcessItems
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $listUri = $Uri

    do {
        $params = @{
            Method      = 'GET'
            Uri         = $listUri
            ErrorAction = 'Stop'
        }
        if ($Headers) { $params['Headers'] = $Headers }

        $response = $null
        try {
            $response = Invoke-MgGraphRequest @params
        } catch {
            # Invoke-MgGraphRequest deserializes JSON into a Dictionary which throws
            # on duplicate keys. Fall back to raw HTTP response + ConvertFrom-Json
            # (returns PSCustomObject where last-key-wins, no error).
            if ($_.Exception.Message -like '*Item has already been added*' -or
                ($_.Exception.InnerException -and $_.Exception.InnerException.Message -like '*Item has already been added*')) {
                Write-Verbose "Dictionary deserialization failed for '$listUri', retrying with raw HTTP response"
                $httpResponse = Invoke-MgGraphRequest @params -OutputType HttpResponseMessage
                $jsonContent = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $response = $jsonContent | ConvertFrom-Json
            } else {
                throw
            }
        }

        $responseValue = if ($null -ne $response.value) { $response.value } else { @() }

        if ($ProcessItems) {
            & $ProcessItems $responseValue
        } else {
            if ($responseValue) {
                $asArray = @($responseValue)
                if ($asArray.Count -gt 0) {
                    $results.AddRange($asArray)
                }
            }
        }

        $listUri = $response.'@odata.nextLink'
    } while ($listUri)

    if (-not $ProcessItems) {
        return , @($results)
    }
}
