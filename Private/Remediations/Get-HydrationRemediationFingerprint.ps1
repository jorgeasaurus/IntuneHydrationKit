function Get-HydrationRemediationFingerprint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template
    )

    $fingerprintInput = [System.Collections.Generic.List[string]]::new()
    foreach ($propertyName in @('templateId', 'displayName', 'publisher', 'description', 'runAsAccount', 'runAs32Bit')) {
        $fingerprintInput.Add("$propertyName=$($Template.$propertyName)")
    }

    foreach ($scriptPath in @($Template.DetectionScriptPath, $Template.RemediationScriptPath)) {
        if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
            $fingerprintInput.Add((Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8))
        }
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($fingerprintInput -join "`n"))
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash)
}
