function Get-RequirementArchitecture {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [object[]]$Architecture
    )

    $architectures = @(Get-NormalizedArchitectures -Architecture $Architecture)
    if ($architectures.Count -ne 1) {
        return 'All'
    }

    return $architectures[0]
}
