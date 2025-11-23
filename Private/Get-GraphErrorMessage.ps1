function Get-GraphErrorMessage {
    <#
    .SYNOPSIS
        Extracts error message from Graph API error response
    .DESCRIPTION
        Internal helper function for parsing Graph API error details
    #>
    param($ErrorRecord)
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return $ErrorRecord.ErrorDetails.Message
    }
    return $ErrorRecord.Exception.Message
}
