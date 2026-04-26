function Get-GraphStatusCode {
    <#
    .SYNOPSIS
        Extracts an HTTP status code from a Graph-related error record
    .DESCRIPTION
        Looks for status code information across the common exception shapes returned by
        Invoke-MgGraphRequest and returns the integer HTTP status code when available.
    #>
    [CmdletBinding()]
    [OutputType([Nullable[int]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCandidates = @(
        $ErrorRecord.Exception.ResponseStatusCode,
        $ErrorRecord.Exception.StatusCode,
        $ErrorRecord.Exception.Response.StatusCode
    )

    foreach ($candidate in $statusCandidates) {
        if ($null -eq $candidate) {
            continue
        }

        if ($candidate -is [int] -or $candidate.GetType().IsEnum) {
            return [int]$candidate
        }

        $parsedStatus = 0
        if ([int]::TryParse([string]$candidate, [ref]$parsedStatus)) {
            return $parsedStatus
        }
    }

    return $null
}
