function Get-MobileAppImportConfiguration {
    <#
    .SYNOPSIS
        Resolves mobile app import settings from the hydration settings hashtable.
    .DESCRIPTION
        Extracts presetId, templateIds, and remediation enabled flag from the
        settings structure, applying sensible defaults and filtering blank values.
    .PARAMETER Settings
        The hydration settings hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    $configuration = @{
        presetId           = $null
        templateIds        = @()
        remediationEnabled = $true
    }

    $mobileApps = Get-ConfigurationSection -InputObject $Settings -Name 'mobileApps'
    if ($mobileApps.Count -eq 0) {
        return $configuration
    }

    if (-not [string]::IsNullOrWhiteSpace($mobileApps.presetId)) {
        $configuration.presetId = [string]$mobileApps.presetId
    }

    if ($null -ne $mobileApps.templateIds) {
        $configuration.templateIds = @(
            $mobileApps.templateIds |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }

    $remediation = Get-ConfigurationSection -InputObject $mobileApps -Name 'remediation'
    if ($remediation.ContainsKey('enabled') -and $null -ne $remediation.enabled) {
        $configuration.remediationEnabled = [bool]$remediation.enabled
    }

    return $configuration
}
