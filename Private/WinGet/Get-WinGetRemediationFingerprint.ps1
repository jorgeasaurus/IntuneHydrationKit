function Get-WinGetRemediationFingerprint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$PackageIdentifiers
    )

    $normalizedIds = @(
        $PackageIdentifiers |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    $joinedIdentifiers = $normalizedIds -join '|'
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($joinedIdentifiers))
    } finally {
        $sha256.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').Substring(0, 16)
}
