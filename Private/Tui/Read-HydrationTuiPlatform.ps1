function Read-HydrationTuiPlatform {
    [CmdletBinding()]
    param()

    $options = @(Get-HydrationTuiPlatformOption)
    Read-HydrationTuiMultiOption `
        -Title 'Platform filter' `
        -Options $options `
        -Prompt 'Select one or more platforms by number, separated by commas; use all for All' `
        -ExclusiveFirst `
        -AllowAllKeyword `
        -ConvertOptions { param($selectedOptions) ConvertTo-HydrationTuiPlatformList -Option $selectedOptions }
}
