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

    $results = @()
    $listUri = $Uri

    do {
        $params = @{
            Method      = 'GET'
            Uri         = $listUri
            ErrorAction = 'Stop'
        }
        if ($Headers) { $params['Headers'] = $Headers }

        $response = Invoke-MgGraphRequest @params

        if ($ProcessItems) {
            & $ProcessItems $response.value
        } else {
            $results += $response.value
        }

        $listUri = $response.'@odata.nextLink'
    } while ($listUri)

    if (-not $ProcessItems) {
        return $results
    }
}
