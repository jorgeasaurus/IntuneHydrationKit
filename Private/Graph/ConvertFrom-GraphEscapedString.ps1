function ConvertFrom-GraphEscapedString {
    <#
    .SYNOPSIS
        Converts escaped characters in Graph API error messages to readable text.
    .DESCRIPTION
        Handles unescaping of common escape sequences (\r\n, \n, \\, \") that appear in Graph API
        error responses. Supports nested message format for inner JSON message extraction.
    .PARAMETER Value
        The escaped string to convert.
    .PARAMETER NestedMessage
        When true, uses less aggressive unescaping (skips \\ → \ conversion) for nested JSON messages.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter()]
        [switch]$NestedMessage
    )

    # Base unescaping: always handle line endings and quotes
    $unescaped = $Value -replace '\\r\\n', ' ' -replace '\\n', ' ' -replace '\\"', '"'

    # Additional unescaping for non-nested messages (includes carriage return and backslash)
    if (-not $NestedMessage) {
        $unescaped = ($unescaped -replace '\\r', ' ').Replace('\\', '\')
    }

    return $unescaped
}
