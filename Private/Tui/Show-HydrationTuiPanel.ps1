function Show-HydrationTuiPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string[]]$Lines = @()
    )

    $palette = Get-HydrationTuiPalette
    $width = Get-HydrationTuiConsoleInnerWidth
    $contentWidth = $width - 4
    $topLeft = [char]0x256D
    $topRight = [char]0x256E
    $bottomLeft = [char]0x2570
    $bottomRight = [char]0x256F
    $horizontal = [char]0x2500
    $vertical = [char]0x2502
    $titleText = " $Title "
    $titleWidth = [Math]::Min($titleText.Length, $contentWidth)
    $leftLine = [Math]::Max(1, [Math]::Floor(($width - 2 - $titleWidth) / 2))
    $rightLine = [Math]::Max(1, $width - 2 - $titleWidth - $leftLine)

    $leftGradient = Get-HydrationTuiGradientLine -Character $horizontal -Width $leftLine
    $rightGradient = Get-HydrationTuiGradientLine -Character $horizontal -Width $rightLine
    $bottomGradient = Get-HydrationTuiGradientLine -Character $horizontal -Width ($width - 2)

    [Console]::WriteLine('')
    [Console]::WriteLine(('  {0}{1}{2}{3}{4}{5}{6}{7}' -f $palette.Surface, $topLeft, $leftGradient, "$($palette.Bold)$($palette.Text)", $titleText, $palette.Reset, $rightGradient, "$($palette.Surface)$topRight$($palette.Reset)"))

    foreach ($line in $Lines) {
        $plainLine = if ($null -eq $line) { '' } else { $line }
        if ($plainLine.Length -gt $contentWidth) {
            $plainLine = $plainLine.Substring(0, [Math]::Max(0, $contentWidth - 3)) + '...'
        }
        [Console]::WriteLine(('  {0}{1}{2} {3}{4}{5} {6}{7}{8}' -f $palette.Surface, $vertical, $palette.Reset, $palette.Text, $plainLine.PadRight($contentWidth), $palette.Reset, $palette.Surface, $vertical, $palette.Reset))
    }

    [Console]::WriteLine(('  {0}{1}{2}{3}{4}' -f $palette.Surface, $bottomLeft, $bottomGradient, $bottomRight, $palette.Reset))
}
