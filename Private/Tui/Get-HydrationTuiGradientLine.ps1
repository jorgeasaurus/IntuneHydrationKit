function Get-HydrationTuiGradientLine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [char]$Character = ([char]0x2500),

        [Parameter()]
        [int]$Width = 1,

        [Parameter()]
        [int[]]$StartRGB = @(30, 64, 175),

        [Parameter()]
        [int[]]$EndRGB = @(56, 189, 248)
    )

    if ($Width -le 0) {
        return ''
    }

    return Get-HydrationTuiGradientString -Text ([string]::new($Character, $Width)) -StartRGB $StartRGB -EndRGB $EndRGB
}
