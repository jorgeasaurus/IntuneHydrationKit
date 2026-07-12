function ConvertTo-HydrationTuiPlatformList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Option
    )

    $selectedOptions = @($Option)

    $selectedPlatforms = [System.Collections.Generic.List[string]]::new()
    foreach ($selectedOption in $selectedOptions) {
        $platform = $selectedOption.Value
        if ($platform -ne 'All' -and -not $selectedPlatforms.Contains($platform)) {
            $selectedPlatforms.Add($platform)
        }
    }

    if ($selectedPlatforms.Count -eq 0) {
        return @('All')
    }

    return $selectedPlatforms.ToArray()
}
