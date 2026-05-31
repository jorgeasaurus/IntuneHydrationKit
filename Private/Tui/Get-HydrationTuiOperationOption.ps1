function Get-HydrationTuiOperationOption {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    @(
        [pscustomobject]@{ Number = 1; Label = 'Create'; Options = @{ create = $true; delete = $false; dryRun = $false } }
        [pscustomobject]@{ Number = 2; Label = 'Dry-run create'; Options = @{ create = $true; delete = $false; dryRun = $true } }
        [pscustomobject]@{ Number = 3; Label = 'Delete'; Options = @{ create = $false; delete = $true; dryRun = $false } }
    )
}
