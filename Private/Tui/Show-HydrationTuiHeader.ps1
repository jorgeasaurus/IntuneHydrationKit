function Show-HydrationTuiHeader {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Lines = @()
    )

    $palette = Get-HydrationTuiPalette
    $consoleWidth = try { [Math]::Max(40, [Console]::WindowWidth) } catch { 80 }
    $centerPad = {
        param([int]$TextWidth)
        [Math]::Max(0, [int](($consoleWidth - $TextWidth) / 2))
    }

    $borderWidth = [Math]::Max(1, [Math]::Min(60, $consoleWidth - 4))
    $gradientTop = Get-HydrationTuiGradientLine -Character ([char]0x2500) -Width $borderWidth
    [Console]::WriteLine('')
    [Console]::WriteLine("$(' ' * (& $centerPad $borderWidth))$gradientTop")

    $bannerLines = Get-HydrationTuiAsciiArt
    $bannerWidth = $bannerLines[0].Length
    $bannerPad = & $centerPad $bannerWidth
    foreach ($line in $bannerLines) {
        [Console]::WriteLine("$(' ' * $bannerPad)$(Get-HydrationTuiGradientString -Text $line)")
    }

    $tagline = 'Intune Hydration Kit'
    [Console]::WriteLine("$(' ' * (& $centerPad $tagline.Length))$($palette.Muted)$tagline$($palette.Reset)")

    $websiteLabel = 'IntuneHydrationKit.com'
    $websiteUrl = 'https://IntuneHydrationKit.com'
    $websiteText = $websiteLabel
    if ($palette.Reset) {
        $escape = [char]0x1B
        $bell = [char]0x07
        $websiteText = "$escape]8;;$websiteUrl$bell$websiteLabel$escape]8;;$bell"
    }
    [Console]::WriteLine("$(' ' * (& $centerPad $websiteLabel.Length))$($palette.Text)$websiteText$($palette.Reset)")

    $credit = 'Made By Jorgeasaurus'
    [Console]::WriteLine("$(' ' * (& $centerPad $credit.Length))$($palette.Muted)$credit$($palette.Reset)")

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $linePad = & $centerPad $line.Length
        [Console]::WriteLine("$(' ' * $linePad)$($palette.Muted)$line$($palette.Reset)")
    }

    $gradientBottom = Get-HydrationTuiGradientLine -Character ([char]0x2500) -Width $borderWidth
    [Console]::WriteLine("$(' ' * (& $centerPad $borderWidth))$gradientBottom")
    [Console]::WriteLine('')
}
