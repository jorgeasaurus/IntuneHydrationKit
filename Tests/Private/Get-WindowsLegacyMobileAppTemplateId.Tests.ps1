#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/MobileApps/Get-WindowsLegacyMobileAppTemplateId.ps1
}

Describe 'Get-WindowsLegacyMobileAppTemplateId' {
    It 'Should return the Windows legacy fallback mobile app template IDs' {
        Get-WindowsLegacyMobileAppTemplateId | Should -Be @(
            'AdobeAcrobatReaderDC',
            'CompanyPortal',
            'PowerShell',
            'SpotifyMusicAndPodcasts',
            'WhatsApp',
            'M365Apps'
        )
    }
}
