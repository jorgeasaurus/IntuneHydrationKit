function Get-HydrationOAuthCallbackResult {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Code,

        [AllowEmptyString()]
        [string]$AuthError,

        [AllowEmptyString()]
        [string]$ErrorDescription,

        [AllowEmptyString()]
        [string]$ReturnedState,

        [Parameter(Mandatory)]
        [string]$ExpectedState
    )

    if ($ReturnedState -ne $ExpectedState) {
        return [PSCustomObject]@{
            Status       = 'Error'
            Message      = 'OAuth state mismatch. Return to PowerShell and try signing in again.'
            ErrorMessage = 'OAuth state mismatch. Aborting authentication.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($Code)) {
        return [PSCustomObject]@{
            Status       = 'Error'
            Message      = $ErrorDescription
            ErrorMessage = "Authorization failed: $AuthError - $ErrorDescription"
        }
    }

    return [PSCustomObject]@{
        Status       = 'Success'
        Message      = $null
        ErrorMessage = $null
    }
}
