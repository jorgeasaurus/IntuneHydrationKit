function Get-HydrationTuiGradientString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter()]
        [int[]]$StartRGB = @(30, 64, 175),

        [Parameter()]
        [int[]]$EndRGB = @(56, 189, 248)
    )

    $palette = Get-HydrationTuiPalette
    if (-not $palette.Reset -or [string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $escape = [char]0x1B
    if ($Text.Length -le 1) {
        return "$escape[38;2;$($StartRGB[0]);$($StartRGB[1]);$($StartRGB[2])m$Text$($palette.Reset)"
    }

    $buffer = [System.Text.StringBuilder]::new($Text.Length * 20)
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $distance = $index / ($Text.Length - 1)
        $red = [int]($StartRGB[0] + (($EndRGB[0] - $StartRGB[0]) * $distance))
        $green = [int]($StartRGB[1] + (($EndRGB[1] - $StartRGB[1]) * $distance))
        $blue = [int]($StartRGB[2] + (($EndRGB[2] - $StartRGB[2]) * $distance))
        $null = $buffer.Append("$escape[38;2;${red};${green};${blue}m$($Text[$index])")
    }

    $null = $buffer.Append($palette.Reset)
    return $buffer.ToString()
}
