function ConvertTo-HydrationTuiImportMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Option
    )

    $options = @(Get-HydrationTuiImportOption)
    $imports = @{}
    foreach ($availableOption in $options) {
        $imports[$availableOption.Key] = $false
    }

    $selectedOptions = @($Option)

    if ($selectedOptions.Count -eq 0) {
        throw 'Select at least one import target.'
    }

    foreach ($selectedOption in $selectedOptions) {
        $imports[$selectedOption.Key] = $true
    }

    return $imports
}
