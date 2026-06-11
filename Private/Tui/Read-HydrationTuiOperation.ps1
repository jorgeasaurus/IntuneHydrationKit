function Read-HydrationTuiOperation {
    [CmdletBinding()]
    param()

    $options = @(Get-HydrationTuiOperationOption)
    Read-HydrationTuiSingleOption `
        -Title 'Operation mode' `
        -Options $options `
        -Prompt 'Select operation' `
        -ConvertOption { param($option) $option.Options }
}
