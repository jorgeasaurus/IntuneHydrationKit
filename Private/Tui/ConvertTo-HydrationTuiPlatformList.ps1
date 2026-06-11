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
        if ($selectedOption.IsExclusive) {
            continue
        }

        $platform = $selectedOption.Value
        if (-not $selectedPlatforms.Contains($platform)) {
            $selectedPlatforms.Add($platform)
        }
    }

    if ($selectedPlatforms.Count -eq 0) {
        return @('All')
    }

    return $selectedPlatforms.ToArray()
}
