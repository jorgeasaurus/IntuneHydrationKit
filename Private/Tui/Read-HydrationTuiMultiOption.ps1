function Read-HydrationTuiMultiOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [object[]]$Options,

        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [scriptblock]$ConvertOptions,

        [Parameter()]
        [switch]$AllowEmpty,

        [Parameter()]
        [object]$EmptyValue,

        [Parameter()]
        [string]$EmptySelectionWarning = 'Select at least one option.',

        [Parameter()]
        [switch]$ExclusiveFirst,

        [Parameter()]
        [switch]$AllowAllKeyword
    )

    $choices = @($Options | ForEach-Object { $_.Label })

    if (Test-HydrationTuiArrowKeySupport) {
        while ($true) {
            $selection = Show-HydrationTuiSelect -Title $Title -Choices $choices -Multiple -ExclusiveFirst:$ExclusiveFirst
            if ($null -eq $selection -or $selection.Cancelled) {
                return $null
            }

            if ($selection.Indices.Count -eq 0) {
                if ($AllowEmpty) {
                    return $EmptyValue
                }

                Write-Warning $EmptySelectionWarning
                continue
            }

            $selectedOptions = @($selection.Indices | ForEach-Object { $Options[$_] })
            return & $ConvertOptions $selectedOptions
        }
    }

    Show-HydrationTuiOptionPanel -Title $Title -Options $Options

    while ($true) {
        $inputResult = Read-HydrationTuiInput -Prompt $Prompt
        if ($inputResult.Cancelled) {
            return $null
        }

        try {
            $selectedOptions = @(Resolve-HydrationTuiOptionSelection `
                    -Options $Options `
                    -Selection $inputResult.Value `
                    -AllowAllKeyword:$AllowAllKeyword)

            if ($selectedOptions.Count -eq 0) {
                if ($AllowEmpty) {
                    return $EmptyValue
                }

                Write-Warning $EmptySelectionWarning
                continue
            }

            return & $ConvertOptions $selectedOptions
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}
