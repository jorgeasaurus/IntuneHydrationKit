function Confirm-HydrationTuiChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [bool]$Default,

        [Parameter()]
        [bool]$ClearScreen = $true
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    if ($ClearScreen) {
        Clear-HydrationTuiScreen
        $null = Show-HydrationTuiHeader
    }

    while ($true) {
        $inputResult = Read-HydrationTuiInput -Prompt "$Prompt $suffix"
        if ($inputResult.Cancelled) {
            return $null
        }

        $value = $inputResult.Value.Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }

        if ($value -in @('y', 'yes')) {
            return $true
        }

        if ($value -in @('n', 'no')) {
            return $false
        }

        Write-Warning 'Enter yes or no.'
    }
}
