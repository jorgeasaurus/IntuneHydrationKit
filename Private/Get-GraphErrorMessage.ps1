function Get-GraphErrorMessage {
    <#
    .SYNOPSIS
        Extracts error message from Graph API error response
    .DESCRIPTION
        Internal helper function for parsing Graph API error details into a clean, readable format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCode = $null
    $errorCode = $null
    $errorMessage = $null

    # Try to get HTTP status code
    if ($ErrorRecord.Exception.Response.StatusCode) {
        $statusCode = [int]$ErrorRecord.Exception.Response.StatusCode
    }

    # Try to parse the JSON error response
    $rawMessage = if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $ErrorRecord.ErrorDetails.Message
    } else {
        $ErrorRecord.Exception.Message
    }

    # Attempt to extract error code from JSON response
    if ($rawMessage -match '"code"\s*:\s*"([^"]+)"') {
        $errorCode = $matches[1]
    }

    # Build a clean error message
    $cleanMessage = switch ($errorCode) {
        'ResourceNotFound' { 'Resource not found (may have been deleted already)' }
        'InternalServerError' { 'Server error - please retry' }
        'BadRequest' { 'Invalid request - check template format' }
        'Forbidden' { 'Access denied - check permissions' }
        'Unauthorized' { 'Authentication failed - reconnect to Graph' }
        'TooManyRequests' { 'Rate limited - please wait and retry' }
        'ServiceUnavailable' { 'Service unavailable - please retry later' }
        default { $errorCode }
    }

    # Format: "HTTP 404: Resource not found" or just the clean message
    if ($statusCode -and $cleanMessage) {
        return "HTTP $statusCode - $cleanMessage"
    }

    if ($cleanMessage) {
        return $cleanMessage
    }

    # Fallback to truncated raw message
    if ($rawMessage.Length -gt 100) {
        return $rawMessage.Substring(0, 100) + '...'
    }

    return $rawMessage
}
