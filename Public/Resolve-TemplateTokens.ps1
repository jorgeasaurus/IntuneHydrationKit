function Resolve-TemplateTokens {
    <#
    .SYNOPSIS
        Resolves placeholder tokens in a template
    .PARAMETER Template
        The template hashtable
    .PARAMETER Tokens
        Hashtable of token replacements
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Template,

        [Parameter(Mandatory = $true)]
        [hashtable]$Tokens
    )

    $json = $Template | ConvertTo-Json -Depth 20

    foreach ($key in $Tokens.Keys) {
        $placeholder = "{{$key}}"
        $json = $json -replace [regex]::Escape($placeholder), $Tokens[$key]
    }

    return $json | ConvertFrom-Json -AsHashtable
}
