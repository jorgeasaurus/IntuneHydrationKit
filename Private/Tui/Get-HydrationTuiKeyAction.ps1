function Get-HydrationTuiKeyAction {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.ConsoleKeyInfo]$KeyInfo
    )

    switch ($KeyInfo.Key) {
        'UpArrow' { return 'MoveUp' }
        'DownArrow' { return 'MoveDown' }
        'Enter' { return 'Confirm' }
        'Escape' { return 'Cancel' }
        'Spacebar' { return 'Toggle' }
    }

    $typedCharacter = $KeyInfo.KeyChar.ToString()
    if ($typedCharacter.Equals('a', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'SelectAll'
    }

    if ($typedCharacter.Equals('q', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Cancel'
    }

    return $null
}
