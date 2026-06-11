function Get-HydrationTuiPlatformOption {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    @(
        [pscustomobject]@{ Number = 0; Label = 'All'; Value = 'All'; IsExclusive = $true }
        [pscustomobject]@{ Number = 1; Label = 'Windows'; Value = 'Windows' }
        [pscustomobject]@{ Number = 2; Label = 'macOS'; Value = 'macOS' }
        [pscustomobject]@{ Number = 3; Label = 'iOS'; Value = 'iOS' }
        [pscustomobject]@{ Number = 4; Label = 'Android'; Value = 'Android' }
        [pscustomobject]@{ Number = 5; Label = 'Linux'; Value = 'Linux' }
    )
}
