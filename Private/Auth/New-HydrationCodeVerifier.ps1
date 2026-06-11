function New-HydrationCodeVerifier {
    [CmdletBinding()]
    param()

    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ConvertTo-HydrationBase64Url -Bytes $bytes
}
