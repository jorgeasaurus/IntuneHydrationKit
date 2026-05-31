function Get-HydrationTuiPalette {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $empty = @{
        Reset     = ''
        Bold      = ''
        Dim       = ''
        Text      = ''
        Muted     = ''
        Accent    = ''
        Highlight = ''
        Border    = ''
        Surface   = ''
        Success   = ''
        Warning   = ''
    }

    if (-not (Test-HydrationTuiArrowKeySupport)) {
        return $empty
    }

    $escape = [char]0x1B
    $infoBlue = "$($PSStyle.Foreground.BrightCyan)"
    return @{
        Reset     = "$escape[0m"
        Bold      = "$escape[1m"
        Dim       = "$escape[2m"
        Text      = $infoBlue
        Muted     = "$escape[38;2;127;132;156m"
        Accent    = $infoBlue
        Highlight = "$escape[48;2;69;71;90m$infoBlue"
        Border    = "$escape[38;2;69;71;90m"
        Surface   = "$escape[38;2;180;190;254m"
        Success   = "$escape[38;2;166;227;161m"
        Warning   = "$escape[38;2;249;226;175m"
    }
}
