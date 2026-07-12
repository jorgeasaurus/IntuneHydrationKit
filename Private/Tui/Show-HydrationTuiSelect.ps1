function Show-HydrationTuiSelect {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Choices,

        [Parameter()]
        [switch]$Multiple,

        [Parameter()]
        [switch]$ExclusiveFirst
    )

    if ($Choices.Count -eq 0) {
        return [pscustomobject]@{
            Cancelled = $false
            Indices   = @()
        }
    }

    $palette = Get-HydrationTuiPalette
    $selectedIndex = 0
    $checked = [bool[]]::new($Choices.Count)
    $instructions = if ($Multiple) {
        if ($ExclusiveFirst) {
            'Space toggles, A selects All, Enter confirms, q cancels.'
        } else {
            'Space toggles, A selects all, Enter confirms, q cancels.'
        }
    } else {
        'Use arrow keys to navigate, Enter to select, q to cancel.'
    }

    try {
        try { [Console]::CursorVisible = $false } catch { $null = $_ }

        while ($true) {
            Clear-HydrationTuiScreen
            Show-HydrationTuiHeader
            Show-HydrationTuiPanel -Title $Title -Lines @($instructions)

            for ($index = 0; $index -lt $Choices.Count; $index++) {
                $prefix = if ($index -eq $selectedIndex) { '  > ' } else { '    ' }
                $style = if ($index -eq $selectedIndex) { $palette.Highlight + $palette.Bold } elseif ($Multiple -and $checked[$index]) { $palette.Success } else { $palette.Text }
                $choiceText = if ($Multiple) {
                    $box = if ($checked[$index]) { '[x]' } else { '[ ]' }
                    "$prefix$box $($Choices[$index])"
                } else {
                    "$prefix$($Choices[$index])"
                }
                [Console]::WriteLine(('{0}{1}{2}' -f $style, $choiceText, $palette.Reset))
            }

            $action = Get-HydrationTuiKeyAction -KeyInfo ([Console]::ReadKey($true))
            if ($Multiple) {
                $state = Update-HydrationTuiMultiSelectState `
                    -SelectedIndex $selectedIndex `
                    -Checked $checked `
                    -Action $action `
                    -ExclusiveFirst:$ExclusiveFirst

                if ($state.Cancelled) {
                    return [pscustomobject]@{
                        Cancelled = $true
                        Indices   = @()
                    }
                }

                if ($state.Confirmed) {
                    $selected = @()
                    for ($index = 0; $index -lt $state.Checked.Count; $index++) {
                        if ($state.Checked[$index]) { $selected += $index }
                    }

                    return [pscustomobject]@{
                        Cancelled = $false
                        Indices   = $selected
                    }
                }

                $selectedIndex = $state.SelectedIndex
                $checked = [bool[]]$state.Checked
                continue
            }

            switch ($action) {
                'MoveUp' {
                    if ($selectedIndex -gt 0) { $selectedIndex-- } else { $selectedIndex = $Choices.Count - 1 }
                }
                'MoveDown' {
                    if ($selectedIndex -lt ($Choices.Count - 1)) { $selectedIndex++ } else { $selectedIndex = 0 }
                }
                'Confirm' {
                    return [pscustomobject]@{
                        Cancelled = $false
                        Indices   = @($selectedIndex)
                    }
                }
                'Cancel' {
                    return [pscustomobject]@{
                        Cancelled = $true
                        Indices   = @()
                    }
                }
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch { $null = $_ }
    }
}
