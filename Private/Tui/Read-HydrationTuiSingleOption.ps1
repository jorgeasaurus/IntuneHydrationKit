function Read-HydrationTuiSingleOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [object[]]$Options,

        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [scriptblock]$ConvertOption
    )

    $choices = @($Options | ForEach-Object { $_.Label })

    if (Test-HydrationTuiArrowKeySupport) {
        $selection = Show-HydrationTuiSelect -Title $Title -Choices $choices
        if ($null -eq $selection -or $selection.Cancelled -or $selection.Indices.Count -eq 0) {
            return $null
        }

        return & $ConvertOption $Options[$selection.Indices[0]]
    }

    Show-HydrationTuiOptionPanel -Title $Title -Options $Options

    while ($true) {
        $inputResult = Read-HydrationTuiInput -Prompt $Prompt
        if ($inputResult.Cancelled) {
            return $null
        }

        try {
            $selectedOptions = @(Resolve-HydrationTuiOptionSelection -Options $Options -Selection $inputResult.Value)
            if ($selectedOptions.Count -ne 1) {
                throw 'Select exactly one option.'
            }

            return & $ConvertOption $selectedOptions[0]
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}
