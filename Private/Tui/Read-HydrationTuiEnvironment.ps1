function Read-HydrationTuiEnvironment {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $options = @(Get-HydrationTuiEnvironmentOption)
    Read-HydrationTuiSingleOption `
        -Title 'Azure cloud environment' `
        -Options $options `
        -Prompt 'Select environment' `
        -ConvertOption { param($option) $option.Value }
}
