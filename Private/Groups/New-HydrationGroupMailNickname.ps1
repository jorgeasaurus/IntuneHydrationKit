function New-HydrationGroupMailNickname {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    $baseName = ($DisplayName -replace '[^a-zA-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = 'group'
    }

    $hashBytes = [System.Security.Cryptography.SHA1]::HashData([System.Text.Encoding]::UTF8.GetBytes($DisplayName))
    $hash = [BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 6).ToLowerInvariant()

    if ($baseName.Length -gt 58) {
        $baseName = $baseName.Substring(0, 58)
    }

    return "$baseName$hash"
}
