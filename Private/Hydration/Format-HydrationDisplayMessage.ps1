function Format-HydrationDisplayMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug', 'Step', 'Section', 'Muted')]
        [string]$Style = 'Info',

        [Parameter()]
        [AllowEmptyString()]
        [string]$Emoji,

        [Parameter()]
        [ValidateRange(0, 16)]
        [int]$Indent = 0
    )

    if ($Message.Length -eq 0) {
        return ''
    }

    $styleMap = @{
        Info    = @{
            Color = "$($PSStyle.Foreground.BrightCyan)"
            Emoji = 'ℹ️'
        }
        Success = @{
            Color = "$($PSStyle.Foreground.BrightGreen)"
            Emoji = '✅'
        }
        Warning = @{
            Color = "$($PSStyle.Foreground.BrightYellow)"
            Emoji = '⚠️'
        }
        Error   = @{
            Color = "$($PSStyle.Foreground.BrightRed)"
            Emoji = '❌'
        }
        Debug   = @{
            Color = "$($PSStyle.Foreground.BrightBlack)"
            Emoji = '🔍'
        }
        Step    = @{
            Color = "$($PSStyle.Bold)$($PSStyle.Foreground.BrightBlue)"
            Emoji = '▶️'
        }
        Section = @{
            Color = "$($PSStyle.Bold)$($PSStyle.Foreground.BrightMagenta)"
            Emoji = '📊'
        }
        Muted   = @{
            Color = "$($PSStyle.Foreground.BrightBlack)"
            Emoji = ''
        }
    }

    $styleSettings = $styleMap[$Style]
    if (-not $PSBoundParameters.ContainsKey('Emoji')) {
        $Emoji = $styleSettings.Emoji
    }

    $indentation = ' ' * $Indent
    $plainMessage = if ([string]::IsNullOrEmpty($Emoji)) {
        '{0}{1}' -f $indentation, $Message
    } else {
        '{0}{1} {2}' -f $indentation, $Emoji, $Message
    }

    if (-not [string]::IsNullOrWhiteSpace($env:NO_COLOR)) {
        return $plainMessage
    }

    $pesterPreference = $ExecutionContext.SessionState.PSVariable.GetValue('PesterPreference', $null)
    if ($null -ne $pesterPreference) {
        return $plainMessage
    }

    if ($null -eq $script:IsPesterLoadedForHydrationDisplayFormatting) {
        $script:IsPesterLoadedForHydrationDisplayFormatting = [bool](Get-Module -Name 'Pester')
    }

    if ($script:IsPesterLoadedForHydrationDisplayFormatting) {
        return $plainMessage
    }

    if ($PSStyle.OutputRendering -eq [System.Management.Automation.OutputRendering]::PlainText) {
        return $plainMessage
    }

    return '{0}{1}{2}' -f $styleSettings.Color, $plainMessage, $PSStyle.Reset
}
