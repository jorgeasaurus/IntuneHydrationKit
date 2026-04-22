function Get-HydrationPlatformFilters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Platforms
    )

    function Get-FilteredPlatforms {
        param(
            [Parameter(Mandatory)]
            [string[]]$ValidSet
        )

        if ($Platforms -contains 'All') {
            return @('All')
        }

        $validPlatforms = $Platforms | Where-Object { $_ -in $ValidSet }
        if ($validPlatforms.Count -eq 0) {
            return @('All')
        }

        return $validPlatforms
    }

    return @{
        Compliance         = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android', 'Linux')
        DeviceFilters      = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android')
        AppProtection      = Get-FilteredPlatforms -ValidSet @('iOS', 'Android')
        MobileApps         = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS')
        EnrollmentProfiles = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS')
        Baseline           = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android')
        CISBaseline        = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android', 'Linux')
        Groups             = Get-FilteredPlatforms -ValidSet @('Windows', 'macOS', 'iOS', 'Android')
    }
}
