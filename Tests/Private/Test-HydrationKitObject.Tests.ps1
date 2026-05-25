#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\'
    Import-Module (Join-Path $modulePath 'IntuneHydrationKit.psd1') -Force
    $script:TestModule = Get-Module -Name IntuneHydrationKit

    . $PSScriptRoot/../../Private/Hydration/Get-HydrationMarkerSet.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
}

Describe 'Test-HydrationKitObject' {
    Context 'Description field only' {
        It 'Should return $true when description contains hydration marker (spaces)' {
            $result = Test-HydrationKitObject -Description 'Some policy - Imported by Intune Hydration Kit'
            $result | Should -BeTrue
        }

        It 'Should return $true when description contains hydration marker (hyphens)' {
            $result = Test-HydrationKitObject -Description 'Policy - Imported by Intune-Hydration-Kit'
            $result | Should -BeTrue
        }

        It 'Should return $false when description has no marker' {
            $result = Test-HydrationKitObject -Description 'Manually created policy'
            $result | Should -BeFalse
        }

        It 'Should return $false when description is null' {
            $result = Test-HydrationKitObject -Description $null
            $result | Should -BeFalse
        }

        It 'Should return $false when description is empty string' {
            $result = Test-HydrationKitObject -Description ''
            $result | Should -BeFalse
        }

        It 'Should return $false when description is whitespace' {
            $result = Test-HydrationKitObject -Description '   '
            $result | Should -BeFalse
        }
    }

    Context 'Notes field only' {
        It 'Should return $true when notes contains hydration marker' {
            $result = Test-HydrationKitObject -Notes 'Imported by Intune Hydration Kit'
            $result | Should -BeTrue
        }

        It 'Should return $false when notes has no marker' {
            $result = Test-HydrationKitObject -Notes 'Admin notes here'
            $result | Should -BeFalse
        }

        It 'Should return $false when notes is null' {
            $result = Test-HydrationKitObject -Notes $null
            $result | Should -BeFalse
        }

        It 'Should return $false when notes is empty string' {
            $result = Test-HydrationKitObject -Notes ''
            $result | Should -BeFalse
        }
    }

    Context 'Both fields provided' {
        It 'Should return $true when description has marker but notes does not' {
            $result = Test-HydrationKitObject -Description 'Imported by Intune Hydration Kit' -Notes 'Admin notes'
            $result | Should -BeTrue
        }

        It 'Should return $true when notes has marker but description does not' {
            $result = Test-HydrationKitObject -Description 'Manual policy' -Notes 'Imported by Intune Hydration Kit'
            $result | Should -BeTrue
        }

        It 'Should return $true when both fields have marker' {
            $result = Test-HydrationKitObject -Description 'Imported by Intune Hydration Kit' -Notes 'Imported by Intune Hydration Kit'
            $result | Should -BeTrue
        }

        It 'Should return $false when neither field has marker' {
            $result = Test-HydrationKitObject -Description 'Manual policy' -Notes 'Admin notes'
            $result | Should -BeFalse
        }

        It 'Should return $false when both fields are null' {
            $result = Test-HydrationKitObject -Description $null -Notes $null
            $result | Should -BeFalse
        }
    }

    Context 'No fields provided' {
        It 'Should return $false when called with no parameters' {
            $result = Test-HydrationKitObject
            $result | Should -BeFalse
        }
    }

    Context 'Backward compatibility' {
        It 'Should work with Description parameter only (existing callers)' {
            $result = Test-HydrationKitObject -Description 'Policy - Imported by Intune Hydration Kit' -ObjectName 'TestPolicy'
            $result | Should -BeTrue
        }
    }

    Context 'Marker source consistency' {
        It 'Should detect both primary and legacy markers from the shared helper' {
            & $script:TestModule {
                $markers = Get-HydrationMarkerSet
                Test-HydrationKitObject -Description $markers.Primary
            } | Should -BeTrue

            & $script:TestModule {
                $markers = Get-HydrationMarkerSet
                Test-HydrationKitObject -Description $markers.Legacy
            } | Should -BeTrue
        }
    }
}
