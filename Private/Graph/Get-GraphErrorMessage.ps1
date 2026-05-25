function Get-GraphErrorMessage {
    <#
    .SYNOPSIS
        Extracts error message from Graph API error response
    .DESCRIPTION
        Internal helper function for parsing Graph API error details into a clean, readable format
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCode = Get-GraphStatusCode -ErrorRecord $ErrorRecord
    $errorCode = $null

    # Try to parse the JSON error response
    $rawMessage = if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $ErrorRecord.ErrorDetails.Message
    } else {
        $ErrorRecord.Exception.Message
    }

    # Attempt to extract error code and detail message from JSON response
    $detailMessage = $null
    if ($rawMessage -match '"code"\s*:\s*"([^"]+)"') {
        $errorCode = $matches[1]
    }

    # Use regex that handles escaped quotes inside the message value
    if ($rawMessage -match '"message"\s*:\s*"((?:[^"\\]|\\.)*)"') {
        $rawDetail = ConvertFrom-GraphEscapedString -Value $matches[1]
        # If the unescaped message looks like JSON, try to extract the inner "Message" field
        if ($rawDetail -match '"Message"\s*:\s*"((?:[^"\\]|\\.)*)"') {
            $detailMessage = ConvertFrom-GraphEscapedString -Value $matches[1] -NestedMessage
        } elseif ($rawDetail.Length -gt 0 -and $rawDetail -ne $errorCode) {
            $detailMessage = $rawDetail
        }
        $detailMessage = Limit-GraphMessage -Message $detailMessage -MaximumLength 200
    }

    # Build a clean error message with detail when available
    $cleanMessage = switch ($errorCode) {
        'ResourceNotFound' { 'Resource not found (may have been deleted already)' }
        'InternalServerError' { 'Server error - please retry' }
        'BadRequest' {
            if ($detailMessage -and $detailMessage -ne 'BadRequest') {
                "Invalid request - $detailMessage"
            } else {
                'Invalid request - check template format'
            }
        }
        'Forbidden' { 'Access denied - check permissions' }
        'Unauthorized' { 'Authentication failed - reconnect to Graph' }
        'TooManyRequests' { 'Rate limited - please wait and retry' }
        'ServiceUnavailable' { 'Service unavailable - please retry later' }
        default {
            if ($detailMessage) {
                "$errorCode - $detailMessage"
            } else {
                $errorCode
            }
        }
    }

    # Format: "HTTP 404: Resource not found" or just the clean message
    if ($cleanMessage) {
        if ($statusCode) {
            return "HTTP $statusCode - $cleanMessage"
        }
        return $cleanMessage
    }

    # Fallback to truncated raw message
    return Limit-GraphMessage -Message $rawMessage -MaximumLength 100
}
