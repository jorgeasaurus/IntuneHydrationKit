function Resolve-HydrationWorkloadPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Imports,

        [Parameter(Mandatory)]
        [string[]]$Platforms,

        [Parameter()]
        [bool]$DeleteEnabled
    )

    function Get-FilteredPlatforms {
        param(
            [Parameter(Mandatory)]
            [string[]]$ValidSet,

            [Parameter(Mandatory)]
            [string[]]$SelectedPlatforms
        )

        if ($SelectedPlatforms -contains 'All') {
            return @('All')
        }

        return @($SelectedPlatforms | Where-Object { $_ -in $ValidSet })
    }

    $workloadCatalog = @(Get-HydrationWorkloadCatalog)
    $deleteIsPlatformScoped = $DeleteEnabled -and $Platforms -and -not ($Platforms -contains 'All')

    $platformFilters = @{}
    foreach ($workload in $workloadCatalog) {
        if ($workload.PlatformNeutral) {
            continue
        }

        if ($platformFilters.ContainsKey($workload.FilterKey)) {
            continue
        }

        $platformFilters[$workload.FilterKey] = Get-FilteredPlatforms -ValidSet $workload.Platforms -SelectedPlatforms $Platforms
    }

    $effectiveImports = @{}
    foreach ($importKey in $Imports.Keys) {
        $effectiveImports[$importKey] = [bool]$Imports[$importKey]
    }

    foreach ($workload in $workloadCatalog) {
        if ($workload.PlatformNeutral) {
            if ($deleteIsPlatformScoped -and $effectiveImports.ContainsKey($workload.ImportKey) -and $effectiveImports[$workload.ImportKey]) {
                $effectiveImports[$workload.ImportKey] = $false
                Write-Verbose "Skipping $($workload.ImportKey) because platform-scoped delete cannot safely target platform-neutral resources."
            }
            continue
        }

        if (-not $effectiveImports.ContainsKey($workload.ImportKey) -or -not $effectiveImports[$workload.ImportKey]) {
            continue
        }

        if (@($platformFilters[$workload.FilterKey]).Count -eq 0) {
            $effectiveImports[$workload.ImportKey] = $false
            Write-Verbose "Skipping $($workload.ImportKey) because selected platform(s) are not supported for that workload."
        }
    }

    return @{
        Imports         = $effectiveImports
        PlatformFilters = $platformFilters
    }
}
