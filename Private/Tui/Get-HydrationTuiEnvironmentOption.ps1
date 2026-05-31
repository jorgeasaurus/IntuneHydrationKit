function Get-HydrationTuiEnvironmentOption {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    @(
        [pscustomobject]@{ Number = 1; Label = 'Global'; Value = 'Global' }
        [pscustomobject]@{ Number = 2; Label = 'US Government'; Value = 'USGov' }
        [pscustomobject]@{ Number = 3; Label = 'US Government DoD'; Value = 'USGovDoD' }
        [pscustomobject]@{ Number = 4; Label = 'Germany'; Value = 'Germany' }
        [pscustomobject]@{ Number = 5; Label = 'China'; Value = 'China' }
    )
}
