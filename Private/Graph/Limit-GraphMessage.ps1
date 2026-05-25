function Limit-GraphMessage {
    <#
    .SYNOPSIS
        Truncates a Graph error message to a maximum length.
    .DESCRIPTION
        Truncates a message string to the specified maximum length and appends ellipsis (...) if truncation occurs.
        Returns the original message if it's shorter than or equal to MaximumLength.
    .PARAMETER Message
        The message to truncate.
    .PARAMETER MaximumLength
        The maximum allowed length for the output message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaximumLength
    )

    if ($null -eq $Message) {
        return ''
    }

    if ($Message.Length -gt $MaximumLength) {
        return $Message.Substring(0, $MaximumLength) + '...'
    }

    return $Message
}
