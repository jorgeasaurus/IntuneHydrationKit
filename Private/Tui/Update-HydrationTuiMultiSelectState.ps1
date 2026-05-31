function Update-HydrationTuiMultiSelectState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [int]$SelectedIndex,

        [Parameter(Mandatory)]
        [bool[]]$Checked,

        [Parameter()]
        [AllowNull()]
        [string]$Action,

        [Parameter()]
        [switch]$ExclusiveFirst
    )

    $nextChecked = [bool[]]$Checked.Clone()
    $count = $nextChecked.Count
    $nextSelectedIndex = $SelectedIndex

    if ($count -eq 0) {
        return [pscustomobject]@{
            SelectedIndex = 0
            Checked       = $nextChecked
            Confirmed     = $false
            Cancelled     = $Action -eq 'Cancel'
        }
    }

    if ($nextSelectedIndex -lt 0) {
        $nextSelectedIndex = 0
    } elseif ($nextSelectedIndex -ge $count) {
        $nextSelectedIndex = $count - 1
    }

    switch ($Action) {
        'MoveUp' {
            if ($nextSelectedIndex -gt 0) { $nextSelectedIndex-- } else { $nextSelectedIndex = $count - 1 }
        }
        'MoveDown' {
            if ($nextSelectedIndex -lt ($count - 1)) { $nextSelectedIndex++ } else { $nextSelectedIndex = 0 }
        }
        'Toggle' {
            $nextChecked[$nextSelectedIndex] = -not $nextChecked[$nextSelectedIndex]
            if ($ExclusiveFirst -and $nextChecked[$nextSelectedIndex]) {
                if ($nextSelectedIndex -eq 0) {
                    for ($index = 1; $index -lt $count; $index++) { $nextChecked[$index] = $false }
                } else {
                    $nextChecked[0] = $false
                }
            }
        }
        'SelectAll' {
            if ($ExclusiveFirst) {
                $nextChecked[0] = $true
                for ($index = 1; $index -lt $count; $index++) { $nextChecked[$index] = $false }
            } else {
                $allChecked = $true
                foreach ($isChecked in $nextChecked) {
                    if (-not $isChecked) {
                        $allChecked = $false
                        break
                    }
                }

                for ($index = 0; $index -lt $count; $index++) { $nextChecked[$index] = -not $allChecked }
            }
        }
    }
    $hasSelection = $nextChecked -contains $true

    [pscustomobject]@{
        SelectedIndex = $nextSelectedIndex
        Checked       = $nextChecked
        Confirmed     = $Action -eq 'Confirm' -and $hasSelection
        Cancelled     = $Action -eq 'Cancel'
    }
}
