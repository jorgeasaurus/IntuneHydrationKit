function Get-HydrationTuiImportOption {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    @(
        [pscustomobject]@{ Number = 1; Key = 'dynamicGroups'; Label = 'Dynamic Groups' }
        [pscustomobject]@{ Number = 2; Key = 'staticGroups'; Label = 'Static Groups' }
        [pscustomobject]@{ Number = 3; Key = 'deviceFilters'; Label = 'Device Filters' }
        [pscustomobject]@{ Number = 4; Key = 'openIntuneBaseline'; Label = 'OpenIntuneBaseline' }
        [pscustomobject]@{ Number = 5; Key = 'cisBaselines'; Label = 'CIS Baselines' }
        [pscustomobject]@{ Number = 6; Key = 'complianceTemplates'; Label = 'Compliance Templates' }
        [pscustomobject]@{ Number = 7; Key = 'appProtection'; Label = 'App Protection' }
        [pscustomobject]@{ Number = 8; Key = 'notificationTemplates'; Label = 'Notification Templates' }
        [pscustomobject]@{ Number = 9; Key = 'enrollmentProfiles'; Label = 'Enrollment Profiles' }
        [pscustomobject]@{ Number = 10; Key = 'conditionalAccess'; Label = 'Conditional Access' }
        [pscustomobject]@{ Number = 11; Key = 'mobileApps'; Label = 'Mobile Apps' }
        [pscustomobject]@{ Number = 12; Key = 'remediations'; Label = 'Proactive Remediations' }
    )
}
