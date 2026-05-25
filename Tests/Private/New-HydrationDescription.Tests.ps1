#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Hydration/Get-HydrationMarkerSet.ps1
    . $PSScriptRoot/../../Private/Hydration/New-HydrationDescription.ps1
}

Describe 'New-HydrationDescription' {
    Context 'When no existing text is provided' {
        It 'Should return just the hydration kit tag' {
            $result = New-HydrationDescription
            $result | Should -Be 'Imported by Intune Hydration Kit'
        }

        It 'Should return just the tag for empty string' {
            $result = New-HydrationDescription -ExistingText ''
            $result | Should -Be 'Imported by Intune Hydration Kit'
        }

        It 'Should return just the tag for null' {
            $result = New-HydrationDescription -ExistingText $null
            $result | Should -Be 'Imported by Intune Hydration Kit'
        }
    }

    Context 'When existing text is provided' {
        It 'Should append tag with separator' {
            $result = New-HydrationDescription -ExistingText 'My policy'
            $result | Should -Be 'My policy - Imported by Intune Hydration Kit'
        }

        It 'Should preserve the original text' {
            $result = New-HydrationDescription -ExistingText 'Windows Security Baseline v2.0'
            $result | Should -BeLike 'Windows Security Baseline v2.0*'
        }

        It 'Should use " - " as separator' {
            $result = New-HydrationDescription -ExistingText 'Existing'
            $result | Should -Match ' - Imported by Intune Hydration Kit$'
        }
    }

    Context 'Tag detection compatibility' {
        It 'Should be detectable by Test-HydrationKitObject' {
            . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
            $desc = New-HydrationDescription -ExistingText 'Test policy'
            Test-HydrationKitObject -Description $desc | Should -BeTrue
        }

        It 'Should be detectable without existing text' {
            . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
            $desc = New-HydrationDescription
            Test-HydrationKitObject -Description $desc | Should -BeTrue
        }
    }

    Context 'When custom separator is provided' {
        It 'Should use space separator' {
            $result = New-HydrationDescription -ExistingText 'My profile' -Separator ' '
            $result | Should -Be 'My profile Imported by Intune Hydration Kit'
        }

        It 'Should use custom separator string' {
            $result = New-HydrationDescription -ExistingText 'Test' -Separator ' | '
            $result | Should -Be 'Test | Imported by Intune Hydration Kit'
        }

        It 'Should still return just the tag when existing text is empty with custom separator' {
            $result = New-HydrationDescription -ExistingText '' -Separator ' '
            $result | Should -Be 'Imported by Intune Hydration Kit'
        }

        It 'Should be detectable by Test-HydrationKitObject with space separator' {
            . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
            $desc = New-HydrationDescription -ExistingText 'Profile' -Separator ' '
            Test-HydrationKitObject -Description $desc | Should -BeTrue
        }
    }
}
