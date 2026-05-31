function Invoke-HydrationTui {
    [CmdletBinding()]
    param()

    $headerLines = @(
        'Bootstrap your Intune environment with best practice defaults.'
        'Interactive setup'
        'Type q at any prompt to cancel.'
    )

    $null = Show-HydrationTuiHeader -Lines $headerLines

    $environment = Read-HydrationTuiEnvironment
    if (-not $environment) {
        return $null
    }

    $operation = Read-HydrationTuiOperation
    if (-not $operation) {
        return $null
    }

    $imports = Read-HydrationTuiImport
    if (-not $imports) {
        return $null
    }

    $platforms = Read-HydrationTuiPlatform
    if (-not $platforms) {
        return $null
    }

    $consentPromptEnabled = Confirm-HydrationTuiChoice -Prompt 'Request Microsoft Graph consent prompt?' -Default:$false
    if ($null -eq $consentPromptEnabled) {
        return $null
    }

    $verboseEnabled = Confirm-HydrationTuiChoice -Prompt 'Enable verbose logging?' -Default:$false
    if ($null -eq $verboseEnabled) {
        return $null
    }

    return @{
        Environment          = $environment
        Operation            = $operation
        Imports              = $imports
        Platforms            = $platforms
        ConsentPromptEnabled = $consentPromptEnabled
        VerboseEnabled       = $verboseEnabled
    }
}
