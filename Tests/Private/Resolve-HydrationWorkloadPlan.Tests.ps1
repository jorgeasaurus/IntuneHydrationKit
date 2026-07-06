#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Configuration/Get-HydrationWorkloadCatalog.ps1
    . $PSScriptRoot/../../Private/Configuration/Resolve-HydrationWorkloadPlan.ps1
    . $PSScriptRoot/../../Private/Tui/Get-HydrationTuiImportOption.ps1
}

Describe 'Get-HydrationWorkloadCatalog' {
    It 'Should represent all import keys exactly once' {
        $expectedKeys = @(
            'dynamicGroups'
            'staticGroups'
            'deviceFilters'
            'openIntuneBaseline'
            'cisBaselines'
            'complianceTemplates'
            'appProtection'
            'enrollmentProfiles'
            'mobileApps'
            'notificationTemplates'
            'conditionalAccess'
        )

        $actualKeys = @(Get-HydrationWorkloadCatalog | ForEach-Object { $_.ImportKey })

        foreach ($expectedKey in $expectedKeys) {
            @($actualKeys | Where-Object { $_ -eq $expectedKey }).Count | Should -Be 1
        }
        $actualKeys.Count | Should -Be $expectedKeys.Count
    }

    It 'Should mark platform-neutral import keys explicitly' {
        $neutralKeys = @(Get-HydrationWorkloadCatalog |
                Where-Object { $_.PlatformNeutral } |
                ForEach-Object { $_.ImportKey })

        $neutralKeys | Should -Contain 'notificationTemplates'
        $neutralKeys | Should -Contain 'conditionalAccess'
    }

    It 'Should keep shared filter keys on identical platform sets' {
        $workloads = @(Get-HydrationWorkloadCatalog | Where-Object { -not $_.PlatformNeutral })
        $sharedGroups = @($workloads | Group-Object FilterKey | Where-Object { $_.Count -gt 1 })

        foreach ($sharedGroup in $sharedGroups) {
            $platformSets = @($sharedGroup.Group | ForEach-Object { (@($_.Platforms) | Sort-Object) -join '|' } | Select-Object -Unique)
            $platformSets | Should -HaveCount 1
        }
    }

    It 'Should match import keys defined by the settings schema' {
        $schema = Get-Content -Raw -Path (Join-Path $PSScriptRoot '../../settings.schema.json') | ConvertFrom-Json
        $schemaKeys = @($schema.properties.imports.properties.PSObject.Properties.Name | Sort-Object)
        $catalogKeys = @(Get-HydrationWorkloadCatalog | ForEach-Object { $_.ImportKey } | Sort-Object)

        $schemaKeys | Should -Be $catalogKeys
    }

    It 'Should match import keys exposed by the TUI selector' {
        $tuiKeys = @(Get-HydrationTuiImportOption | ForEach-Object { $_.Key } | Sort-Object)
        $catalogKeys = @(Get-HydrationWorkloadCatalog | ForEach-Object { $_.ImportKey } | Sort-Object)

        $tuiKeys | Should -Be $catalogKeys
    }
}

Describe 'Resolve-HydrationWorkloadPlan' {
    It 'Should disable imports whose selected platforms are unsupported' {
        $imports = @{
            mobileApps             = $true
            deviceFilters          = $true
            appProtection          = $true
            enrollmentProfiles     = $true
            openIntuneBaseline     = $true
            dynamicGroups          = $true
            staticGroups           = $true
            complianceTemplates    = $true
            cisBaselines           = $true
            notificationTemplates  = $true
            conditionalAccess      = $true
        }

        $result = Resolve-HydrationWorkloadPlan -Imports $imports -Platforms Linux

        $result.Imports.mobileApps | Should -BeFalse
        $result.Imports.deviceFilters | Should -BeFalse
        $result.Imports.appProtection | Should -BeFalse
        $result.Imports.enrollmentProfiles | Should -BeFalse
        $result.Imports.openIntuneBaseline | Should -BeFalse
        $result.Imports.dynamicGroups | Should -BeFalse
        $result.Imports.staticGroups | Should -BeFalse
        $result.Imports.complianceTemplates | Should -BeTrue
        $result.Imports.cisBaselines | Should -BeTrue
        $result.Imports.notificationTemplates | Should -BeTrue
        $result.Imports.conditionalAccess | Should -BeTrue
        $result.PlatformFilters.MobileApps | Should -BeNullOrEmpty
        $result.PlatformFilters.Compliance | Should -Be @('Linux')
        $result.PlatformFilters.CISBaseline | Should -Be @('Linux')
    }

    It 'Should keep supported imports enabled' {
        $imports = @{
            mobileApps = $true
            appProtection = $true
        }

        $result = Resolve-HydrationWorkloadPlan -Imports $imports -Platforms iOS

        $result.Imports.mobileApps | Should -BeFalse
        $result.Imports.appProtection | Should -BeTrue
        $result.PlatformFilters.AppProtection | Should -Be @('iOS')
    }

    It 'Should keep All as the platform filter for platform-scoped workloads' {
        $imports = @{
            deviceFilters = $true
            mobileApps = $true
        }

        $result = Resolve-HydrationWorkloadPlan -Imports $imports -Platforms All

        $result.PlatformFilters.DeviceFilters | Should -Be @('All')
        $result.PlatformFilters.MobileApps | Should -Be @('All')
        $result.Imports.deviceFilters | Should -BeTrue
        $result.Imports.mobileApps | Should -BeTrue
    }

    It 'Should disable platform-neutral workloads during platform-scoped delete' {
        $imports = @{
            notificationTemplates = $true
            conditionalAccess = $true
            complianceTemplates = $true
        }

        $result = Resolve-HydrationWorkloadPlan -Imports $imports -Platforms Linux -DeleteEnabled $true

        $result.Imports.notificationTemplates | Should -BeFalse
        $result.Imports.conditionalAccess | Should -BeFalse
        $result.Imports.complianceTemplates | Should -BeTrue
    }

    It 'Should keep platform-neutral workloads enabled during platform-scoped create' {
        $imports = @{
            notificationTemplates = $true
            conditionalAccess = $true
        }

        $result = Resolve-HydrationWorkloadPlan -Imports $imports -Platforms Linux

        $result.Imports.notificationTemplates | Should -BeTrue
        $result.Imports.conditionalAccess | Should -BeTrue
    }

}
