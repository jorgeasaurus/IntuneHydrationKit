function Get-HydrationWorkloadCatalog {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{
            ImportKey = 'dynamicGroups'
            FilterKey = 'Groups'
            Platforms = @('Windows', 'macOS', 'iOS', 'Android')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'staticGroups'
            FilterKey = 'Groups'
            Platforms = @('Windows', 'macOS', 'iOS', 'Android')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'deviceFilters'
            FilterKey = 'DeviceFilters'
            Platforms = @('Windows', 'macOS', 'iOS', 'Android')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'openIntuneBaseline'
            FilterKey = 'Baseline'
            Platforms = @('Windows', 'macOS', 'iOS', 'Android')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'cisBaselines'
            FilterKey = 'CISBaseline'
            Platforms = @('Windows', 'macOS', 'iOS', 'Android', 'Linux')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'complianceTemplates'
            FilterKey = 'Compliance'
            Platforms = @('Windows', 'macOS', 'iOS', 'Android', 'Linux')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'appProtection'
            FilterKey = 'AppProtection'
            Platforms = @('iOS', 'Android')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'enrollmentProfiles'
            FilterKey = 'EnrollmentProfiles'
            Platforms = @('Windows', 'macOS')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'mobileApps'
            FilterKey = 'MobileApps'
            Platforms = @('Windows', 'macOS')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'remediations'
            FilterKey = 'Remediations'
            Platforms = @('Windows')
            PlatformNeutral = $false
        }
        [pscustomobject]@{
            ImportKey = 'notificationTemplates'
            FilterKey = $null
            Platforms = @()
            PlatformNeutral = $true
        }
        [pscustomobject]@{
            ImportKey = 'conditionalAccess'
            FilterKey = $null
            Platforms = @()
            PlatformNeutral = $true
        }
    )
}
