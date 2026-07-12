#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Hydration/Get-HydrationMarkerSet.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
    . $PSScriptRoot/../../Private/WinGet/Test-IntuneWinGetAppOwnership.ps1
}

Describe 'Test-IntuneWinGetAppOwnership' {
    It 'Should return true when both hydration and WinGet markers exist' {
        $result = Test-IntuneWinGetAppOwnership -Description 'Line of business app - Imported by Intune Hydration Kit' -Notes "Imported from WinGet`nWinGetPackageIdentifier: Contoso.App"

        $result | Should -BeTrue
    }

    It 'Should return false when the hydration marker is missing' {
        $result = Test-IntuneWinGetAppOwnership -Description 'Manual app' -Notes 'Imported from WinGet'

        $result | Should -BeFalse
    }

    It 'Should return false when the WinGet marker is missing' {
        $result = Test-IntuneWinGetAppOwnership -Description 'Manual app - Imported by Intune Hydration Kit' -Notes 'Operational note only'

        $result | Should -BeFalse
    }
}
