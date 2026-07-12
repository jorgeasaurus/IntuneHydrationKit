function Resolve-ApplicableArchitecture {
    <#
    .SYNOPSIS
        Resolves a requirement architecture value to a Graph payload value.
    .DESCRIPTION
        Returns `$null` for empty values or `All`; returns supported values unchanged.
    .PARAMETER Architecture
        Architecture value from configuration.
    .OUTPUTS
        string
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Architecture
    )

    if ([string]::IsNullOrWhiteSpace($Architecture) -or $Architecture -eq 'All') {
        return $null
    }

    if ($Architecture -in @('x64', 'x86', 'arm64')) {
        return $Architecture
    }

    return $null
}
