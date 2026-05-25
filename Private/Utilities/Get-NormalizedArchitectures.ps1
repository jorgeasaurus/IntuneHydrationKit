function Get-NormalizedArchitectures {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [object[]]$Architecture
    )

    return @(
        $Architecture |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { [string]$_ }
    )
}
