function Get-UploadUriForLogging {
    <#
    .SYNOPSIS
        Strips the query string from an Azure Storage upload URI for safe logging.
    .PARAMETER Uri
        Upload URI that may contain a SAS token query string.
    .OUTPUTS
        string
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    return ($Uri -split '\?', 2)[0]
}
