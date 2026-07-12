function Read-HydrationTuiImport {
    [CmdletBinding()]
    param()

    $options = @(Get-HydrationTuiImportOption)
    Read-HydrationTuiMultiOption `
        -Title 'Import targets' `
        -Options $options `
        -Prompt 'Select one or more targets by number, separated by commas' `
        -EmptySelectionWarning 'Select at least one import target.' `
        -ConvertOptions { param($selectedOptions) ConvertTo-HydrationTuiImportMap -Option $selectedOptions }
}
