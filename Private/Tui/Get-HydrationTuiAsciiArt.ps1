function Get-HydrationTuiAsciiArt {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $bannerLines = @(
        '██╗██╗  ██╗██████╗ '
        '██║██║  ██║██╔══██╗'
        '██║███████║██║  ██║'
        '██║██╔══██║██║  ██║'
        '██║██║  ██║██████╔╝'
        '╚═╝╚═╝  ╚═╝╚═════╝ '
    )

    return $bannerLines
}
