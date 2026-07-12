function Get-HydrationTuiConsoleInnerWidth {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    try {
        return [Math]::Max(48, [Console]::WindowWidth - 4)
    } catch {
        return 80
    }
}
