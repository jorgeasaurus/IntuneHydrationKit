function Get-PrimaryArchitecture {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [object[]]$Architecture
    )

    $architectures = @(Get-NormalizedArchitectures -Architecture $Architecture)
    if ($architectures.Count -eq 0) {
        return 'All'
    }

    return $architectures[0]
}
