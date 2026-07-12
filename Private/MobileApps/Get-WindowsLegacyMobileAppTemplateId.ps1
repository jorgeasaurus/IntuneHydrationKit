function Get-WindowsLegacyMobileAppTemplateId {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        'AdobeAcrobatReaderDC',
        'CompanyPortal',
        'PowerShell',
        'SpotifyMusicAndPodcasts',
        'WhatsApp',
        'M365Apps'
    )
}
