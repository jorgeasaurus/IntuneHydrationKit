function Clear-HydrationTuiScreen {
    [CmdletBinding()]
    param()

    try {
        [Console]::Clear()
    } catch {
        $null = $_
    }
}
