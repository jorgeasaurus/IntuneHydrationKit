function New-WinGetRemediationDescription {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string[]]$PackageIdentifiers
    )

    $scopeLabel = if ($Scope -eq 'system') { 'system' } else { 'user' }
    $fingerprint = Get-WinGetRemediationFingerprint -PackageIdentifiers $PackageIdentifiers

    return @(
        "Auto-update remediation for WinGet apps ($scopeLabel scope)."
        $script:HydrationMarker
        'Imported from WinGet'
        "WinGetRemediationScope: $scopeLabel"
        "WinGetPackageCount: $(@($PackageIdentifiers | Sort-Object -Unique).Count)"
        "WinGetPackageFingerprint: $fingerprint"
    ) -join [Environment]::NewLine
}
