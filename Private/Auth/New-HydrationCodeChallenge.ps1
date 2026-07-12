function New-HydrationCodeChallenge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Verifier
    )

    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Verifier))
    return [Convert]::ToBase64String($hash).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
