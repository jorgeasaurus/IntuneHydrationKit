#Requires -Modules Pester

BeforeAll {
    # Import the functions under test
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Get-FilteredTemplates.ps1'
    $hydrationTemplatesPath = Join-Path $PSScriptRoot '..\..\Private\Get-HydrationTemplates.ps1'
    . $functionPath
    . $hydrationTemplatesPath
}

Describe 'Get-FilteredTemplates' {
    BeforeAll {
        # Helper function to create mock FileInfo objects
        function New-MockFileInfo {
            param(
                [string]$Name,
                [string]$DirectoryName
            )
            [PSCustomObject]@{
                Name          = $Name
                DirectoryName = $DirectoryName
                FullName      = "$DirectoryName/$Name"
            }
        }
    }

    Context 'When Platform is All or not specified' {
        It 'Should return all templates when Platform is All' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'macOS-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'iOS-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'All'

            $result | Should -HaveCount 3
        }

        It 'Should return all templates when Platform parameter is not specified' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'macOS-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates'

            $result | Should -HaveCount 2
        }

        It 'Should return all templates when Platform array contains All' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Android-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform @('Windows', 'All')

            $result | Should -HaveCount 2
        }

        It 'Should return no templates when Platform is explicitly empty' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Android-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform @()

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When using Prefix filter mode' {
        It 'Should filter templates by Windows prefix' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Compliance.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Windows_Security.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'macOS-Compliance.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'iOS-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'Windows-Compliance.json'
            $result.Name | Should -Contain 'Windows_Security.json'
        }

        It 'Should match Win prefix for Windows platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Win-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Win_Updates.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'macOS-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'Win-Policy.json'
            $result.Name | Should -Contain 'Win_Updates.json'
        }

        It 'Should filter templates by macOS prefix' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'macOS-Compliance.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'macOS_Security.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'macOS' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'macOS-Compliance.json'
            $result.Name | Should -Contain 'macOS_Security.json'
        }

        It 'Should match mac prefix for macOS platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'mac-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'mac_Updates.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'macOS' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'mac-Policy.json'
            $result.Name | Should -Contain 'mac_Updates.json'
        }

        It 'Should filter templates by iOS prefix' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'iOS-AppProtection.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'iOS_MAM.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Android-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'iOS' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
        }

        It 'Should filter templates by Android prefix' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Android-AppProtection.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Android_MAM.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'iOS-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Android' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
        }

        It 'Should filter templates by Linux prefix' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Linux-Compliance.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Linux_Security.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Linux' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
        }

        It 'Should be case-insensitive for prefix matching' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'WINDOWS-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'windows-Security.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Windows-Compliance.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -HaveCount 3
        }
    }

    Context 'When using Suffix filter mode' {
        It 'Should filter templates by Windows suffix' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Compliance-Windows.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Security_Windows.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Policy-macOS.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Suffix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'Compliance-Windows.json'
            $result.Name | Should -Contain 'Security_Windows.json'
        }

        It 'Should filter templates by iOS suffix' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'MAM-iOS.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'AppProtection_iOS.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'MAM-Android.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'iOS' -FilterMode 'Suffix'

            $result | Should -HaveCount 2
        }

        It 'Should be case-insensitive for suffix matching' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Policy-WINDOWS.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Policy-windows.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Policy-Windows.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Suffix'

            $result | Should -HaveCount 3
        }
    }

    Context 'When using Directory filter mode' {
        It 'Should filter templates by parent directory name' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Compliance.json' -DirectoryName 'C:\Templates\Windows'
                New-MockFileInfo -Name 'Security.json' -DirectoryName 'C:\Templates\Windows'
                New-MockFileInfo -Name 'Policy.json' -DirectoryName 'C:\Templates\macOS'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Directory'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'Compliance.json'
            $result.Name | Should -Contain 'Security.json'
        }

        It 'Should match Mac directory for macOS platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Policy.json' -DirectoryName 'C:\Templates\Mac'
                New-MockFileInfo -Name 'Security.json' -DirectoryName 'C:\Templates\macOS'
                New-MockFileInfo -Name 'Windows.json' -DirectoryName 'C:\Templates\Windows'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'macOS' -FilterMode 'Directory'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'Policy.json'
            $result.Name | Should -Contain 'Security.json'
        }

        It 'Should filter by iOS directory' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'AppProtection.json' -DirectoryName 'C:\Templates\iOS'
                New-MockFileInfo -Name 'MAM.json' -DirectoryName 'C:\Templates\Android'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'iOS' -FilterMode 'Directory'

            $result | Should -HaveCount 1
            $result.Name | Should -Be 'AppProtection.json'
        }

        It 'Should match nested Windows path segments for mobile app templates' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'CompanyPortal.json' -DirectoryName 'Templates/MobileApps/Windows/Store'
                New-MockFileInfo -Name 'M365.json' -DirectoryName 'Templates/MobileApps/Windows/M365'
                New-MockFileInfo -Name 'MacApp.json' -DirectoryName 'Templates/MobileApps/macOS/Store'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'Templates/MobileApps' -Platform 'Windows' -FilterMode 'Directory' -Recurse

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'CompanyPortal.json'
            $result.Name | Should -Contain 'M365.json'
        }

        It 'Should match nested directories when paths use mixed separators' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'CompanyPortal.json' -DirectoryName 'Templates\MobileApps/Windows\Store'
                New-MockFileInfo -Name 'MacApp.json' -DirectoryName 'Templates\MobileApps/macOS\Store'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'Templates/MobileApps' -Platform 'Windows' -FilterMode 'Directory' -Recurse

            $result | Should -HaveCount 1
            $result.Name | Should -Be 'CompanyPortal.json'
        }
    }

    Context 'When using Folder filter mode (OpenIntuneBaseline structure)' {
        It 'Should match WINDOWS folder for Windows platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Policy.json' -DirectoryName 'C:\Baseline\WINDOWS\Security'
                New-MockFileInfo -Name 'Compliance.json' -DirectoryName 'C:\Baseline\WINDOWS'
                New-MockFileInfo -Name 'Mac.json' -DirectoryName 'C:\Baseline\MACOS'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Baseline' -Platform 'Windows' -FilterMode 'Folder'

            $result | Should -HaveCount 2
        }

        It 'Should match WINDOWS365 folder for Windows platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'CloudPC.json' -DirectoryName 'C:\Baseline\WINDOWS365'
                New-MockFileInfo -Name 'Security.json' -DirectoryName 'C:\Baseline\WINDOWS365\Policies'
                New-MockFileInfo -Name 'Mac.json' -DirectoryName 'C:\Baseline\MACOS'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Baseline' -Platform 'Windows' -FilterMode 'Folder'

            $result | Should -HaveCount 2
        }

        It 'Should match MACOS folder for macOS platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Security.json' -DirectoryName 'C:\Baseline\MACOS'
                New-MockFileInfo -Name 'Policy.json' -DirectoryName 'C:\Baseline\MACOS\Config'
                New-MockFileInfo -Name 'Win.json' -DirectoryName 'C:\Baseline\WINDOWS'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Baseline' -Platform 'macOS' -FilterMode 'Folder'

            $result | Should -HaveCount 2
        }

        It 'Should match BYOD folder with iOS in filename for iOS platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'iOS-AppProtection.json' -DirectoryName 'C:\Baseline\BYOD'
                New-MockFileInfo -Name 'iOS_MAM.json' -DirectoryName 'C:\Baseline\BYOD\Policies'
                New-MockFileInfo -Name 'Android-MAM.json' -DirectoryName 'C:\Baseline\BYOD'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Baseline' -Platform 'iOS' -FilterMode 'Folder'

            $result | Should -HaveCount 2
            $result.Name | Should -Not -Contain 'Android-MAM.json'
        }

        It 'Should match BYOD folder with Android in filename for Android platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Android-AppProtection.json' -DirectoryName 'C:\Baseline\BYOD'
                New-MockFileInfo -Name 'Android_MAM.json' -DirectoryName 'C:\Baseline\BYOD\Policies'
                New-MockFileInfo -Name 'iOS-MAM.json' -DirectoryName 'C:\Baseline\BYOD'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Baseline' -Platform 'Android' -FilterMode 'Folder'

            $result | Should -HaveCount 2
            $result.Name | Should -Not -Contain 'iOS-MAM.json'
        }
    }

    Context 'When filtering by multiple platforms' {
        It 'Should return templates matching any of the specified platforms' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'macOS-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'iOS-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Android-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform @('Windows', 'macOS') -FilterMode 'Prefix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'Windows-Policy.json'
            $result.Name | Should -Contain 'macOS-Policy.json'
        }

        It 'Should return templates for iOS and Android platforms' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'iOS-MAM.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Android-MAM.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform @('iOS', 'Android') -FilterMode 'Prefix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'iOS-MAM.json'
            $result.Name | Should -Contain 'Android-MAM.json'
        }

        It 'Should return templates for all specified platforms across filter modes' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Policy-Windows.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Policy-Linux.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Policy-macOS.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform @('Windows', 'Linux') -FilterMode 'Suffix'

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'Policy-Windows.json'
            $result.Name | Should -Contain 'Policy-Linux.json'
        }
    }

    Context 'When no templates match the filter' {
        It 'Should return empty result when no templates match platform' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'macOS-Policy.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'iOS-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -BeNullOrEmpty
        }

        It 'Should return empty result when source directory is empty' {
            Mock Get-HydrationTemplates { return @() }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -BeNullOrEmpty
        }

        It 'Should return empty result when Get-HydrationTemplates returns null' {
            Mock Get-HydrationTemplates { return $null }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When using Recurse parameter' {
        It 'Should pass Recurse parameter to Get-HydrationTemplates' {
            Mock Get-HydrationTemplates { return @() } -ParameterFilter { $Recurse -eq $true }

            Get-FilteredTemplates -Path 'C:\Templates' -Recurse

            Should -Invoke Get-HydrationTemplates -Times 1 -ParameterFilter { $Recurse -eq $true }
        }

        It 'Should not pass Recurse when not specified' {
            Mock Get-HydrationTemplates { return @() } -ParameterFilter { $Recurse -eq $false }

            Get-FilteredTemplates -Path 'C:\Templates'

            Should -Invoke Get-HydrationTemplates -Times 1 -ParameterFilter { $Recurse -eq $false }
        }
    }

    Context 'When using ResourceType parameter' {
        It 'Should pass ResourceType parameter to Get-HydrationTemplates' {
            Mock Get-HydrationTemplates { return @() } -ParameterFilter { $ResourceType -eq 'compliance policy' }

            Get-FilteredTemplates -Path 'C:\Templates' -ResourceType 'compliance policy'

            Should -Invoke Get-HydrationTemplates -Times 1 -ParameterFilter { $ResourceType -eq 'compliance policy' }
        }

        It 'Should use default ResourceType when not specified' {
            Mock Get-HydrationTemplates { return @() } -ParameterFilter { $ResourceType -eq 'template' }

            Get-FilteredTemplates -Path 'C:\Templates'

            Should -Invoke Get-HydrationTemplates -Times 1 -ParameterFilter { $ResourceType -eq 'template' }
        }
    }

    Context 'Parameter validation' {
        It 'Should require Path parameter' {
            { Get-FilteredTemplates -Platform 'Windows' } | Should -Throw
        }

        It 'Should validate Platform parameter values' {
            Mock Get-HydrationTemplates { return @() }

            { Get-FilteredTemplates -Path 'C:\Templates' -Platform 'InvalidPlatform' } | Should -Throw
        }

        It 'Should validate FilterMode parameter values' {
            Mock Get-HydrationTemplates { return @() }

            { Get-FilteredTemplates -Path 'C:\Templates' -FilterMode 'InvalidMode' } | Should -Throw
        }

        It 'Should accept all valid Platform values' {
            Mock Get-HydrationTemplates { return @() }

            $validPlatforms = @('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')

            foreach ($platform in $validPlatforms) {
                { Get-FilteredTemplates -Path 'C:\Templates' -Platform $platform } | Should -Not -Throw
            }
        }

        It 'Should accept all valid FilterMode values' {
            Mock Get-HydrationTemplates { return @() }

            $validModes = @('Prefix', 'Suffix', 'Directory', 'Folder')

            foreach ($mode in $validModes) {
                { Get-FilteredTemplates -Path 'C:\Templates' -FilterMode $mode } | Should -Not -Throw
            }
        }
    }

    Context 'Edge cases' {
        It 'Should handle templates with special characters in filename' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy (v2).json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Windows_Policy[1].json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -HaveCount 2
        }

        It 'Should handle single template result' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            $result | Should -HaveCount 1
            $result.Name | Should -Be 'Windows-Policy.json'
        }

        It 'Should not match partial platform names in prefix mode' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'WindowsUpdate.json' -DirectoryName 'C:\Templates'
                New-MockFileInfo -Name 'Windows-Policy.json' -DirectoryName 'C:\Templates'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Templates' -Platform 'Windows' -FilterMode 'Prefix'

            # WindowsUpdate.json should NOT match because there's no separator after 'Windows'
            $result | Should -HaveCount 1
            $result.Name | Should -Be 'Windows-Policy.json'
        }

        It 'Should handle deeply nested directory paths' {
            $mockTemplates = @(
                New-MockFileInfo -Name 'Policy.json' -DirectoryName 'C:\Root\Level1\Level2\Level3\Windows'
            )

            Mock Get-HydrationTemplates { return $mockTemplates }

            $result = Get-FilteredTemplates -Path 'C:\Root' -Platform 'Windows' -FilterMode 'Directory'

            $result | Should -HaveCount 1
        }
    }
}
