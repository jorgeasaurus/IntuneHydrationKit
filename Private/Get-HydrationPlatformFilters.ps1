function Get-HydrationPlatformFilters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Platforms
    )

    function Get-FilteredPlatforms {
        param(
            [Parameter(Mandatory)]
            [string[]]$ValidSet,

            [Parameter(Mandatory)]
            [string[]]$SelectedPlatforms
        )

        if ($SelectedPlatforms -contains 'All') {
            return @('All')
        }

        $validPlatforms = $SelectedPlatforms | Where-Object { $_ -in $ValidSet }
        if ($validPlatforms.Count -eq 0) {
            return @('All')
        }

        return $validPlatforms
    }

    return @{
        Compliance         = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android', 'Linux') -SelectedPlatforms $Platforms
        DeviceFilters      = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android') -SelectedPlatforms $Platforms
        AppProtection      = Get-FilteredPlatforms -ValidSet @('iOS', 'Android') -SelectedPlatforms $Platforms
        MobileApps         = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS') -SelectedPlatforms $Platforms
        EnrollmentProfiles = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS') -SelectedPlatforms $Platforms
        Baseline           = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android') -SelectedPlatforms $Platforms
        CISBaseline        = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android', 'Linux') -SelectedPlatforms $Platforms
        Groups             = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android') -SelectedPlatforms $Platforms
    }
}
