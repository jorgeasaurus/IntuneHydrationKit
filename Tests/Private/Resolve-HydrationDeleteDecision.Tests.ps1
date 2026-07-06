#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Hydration/Get-HydrationMarkerSet.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationTemplateNameMatch.ps1
    . $PSScriptRoot/../../Private/MobileApps/Get-HydrationMobileAppBaseName.ps1
    . $PSScriptRoot/../../Private/MobileApps/Get-HydrationMobileAppDisplayName.ps1
    . $PSScriptRoot/../../Private/MobileApps/Get-HydrationMobileAppNameVariant.ps1
    . $PSScriptRoot/../../Private/MobileApps/Test-HydrationMobileAppNameInSet.ps1
    . $PSScriptRoot/../../Private/Hydration/Resolve-HydrationDeleteDecision.ps1
    $script:ImportPrefix = '[IHD] '
    $script:HydrationMarker = 'Imported by Intune Hydration Kit'
    $script:HydrationMarkerAlt = 'Imported by Intune-Hydration-Kit'
}

Describe 'Resolve-HydrationDeleteDecision' {
    BeforeEach {
        $script:names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [void]$script:names.Add('Windows Filter')
    }

    It 'Should match prefixed hydration objects to unprefixed template names' {
        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Windows Filter' `
            -Description 'Imported by Intune Hydration Kit' `
            -KnownTemplateNames $script:names

        $result.IsMatch | Should -BeTrue
        $result.NeedsFullObject | Should -BeFalse
        $result.Reason | Should -Be 'Delete'
        $result.MatchesTemplateName | Should -BeTrue
    }

    It 'Should reject hydration objects that are outside the template scope' {
        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Other Filter' `
            -Description 'Imported by Intune Hydration Kit' `
            -KnownTemplateNames $script:names

        $result.IsMatch | Should -BeFalse
        $result.NeedsFullObject | Should -BeFalse
        $result.Reason | Should -Be 'TemplateNameNotInScope'
        $result.Message | Should -Be 'not in current template set'
    }

    It 'Should reject unmarked objects even when names match' {
        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Windows Filter' `
            -Description 'Manual object' `
            -KnownTemplateNames $script:names

        $result.IsMatch | Should -BeFalse
        $result.NeedsFullObject | Should -BeFalse
        $result.Reason | Should -Be 'NotHydrationKitObject'
        $result.Message | Should -Be 'not created by Intune Hydration Kit'
    }

    It 'Should fail closed when template matching is required but no template names are available' {
        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Windows Filter' `
            -Description 'Imported by Intune Hydration Kit'

        $result.IsMatch | Should -BeFalse
        $result.NeedsFullObject | Should -BeFalse
        $result.Reason | Should -Be 'TemplateNameSetMissing'
    }

    It 'Should ask callers to verify the full object when marker fields are missing' {
        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Windows Filter' `
            -KnownTemplateNames $script:names

        $result.IsMatch | Should -BeFalse
        $result.NeedsFullObject | Should -BeTrue
        $result.Reason | Should -Be 'NeedsMarkerVerification'
    }

    It 'Should match name-only resources through the same decision shape' {
        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Windows Filter' `
            -KnownTemplateNames $script:names `
            -NameOnly

        $result.IsMatch | Should -BeTrue
        $result.NeedsFullObject | Should -BeFalse
        $result.Reason | Should -Be 'Delete'
        $result.MatchesTemplateName | Should -BeTrue
    }

    It 'Should reject marker-only deletes when the name is out of scope' {
        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Other Filter' `
            -Description 'Imported by Intune Hydration Kit' `
            -KnownTemplateNames $script:names

        $result.IsMatch | Should -BeFalse
        $result.Reason | Should -Be 'TemplateNameNotInScope'
    }

    It 'Should support mobile app name variants through the same decision shape' {
        $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [void]$nameSet.Add('Company Portal - [IHD]')

        $result = Resolve-HydrationDeleteDecision `
            -Name '[IHD] Company Portal' `
            -Notes 'Imported by Intune Hydration Kit' `
            -KnownTemplateNames $nameSet `
            -MobileAppName

        $result.IsMatch | Should -BeTrue
        $result.Reason | Should -Be 'Delete'
    }

    It 'Should support externally verified ownership through the same decision shape' {
        $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [void]$nameSet.Add('Company Portal - [IHD]')

        $result = Resolve-HydrationDeleteDecision `
            -Name 'Company Portal - [IHD]' `
            -KnownTemplateNames $nameSet `
            -MobileAppName `
            -RequireOwnership `
            -IsOwned $true `
            -OwnershipFailureMessage 'not owned by WinGet hydration importer'

        $result.IsMatch | Should -BeTrue
        $result.Reason | Should -Be 'Delete'
    }
}
