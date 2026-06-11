function Get-HydrationMobileAppRemediationEnabled {
    <#
    .SYNOPSIS
        Resolves whether WinGet proactive remediation is enabled for a mobile app configuration.
    .DESCRIPTION
        Defaults to enabled when the configuration is absent or does not specify a value.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [hashtable]$Configuration = @{}
    )

    if ($Configuration -and $Configuration.ContainsKey('remediationEnabled') -and $null -ne $Configuration.remediationEnabled) {
        return [bool]$Configuration.remediationEnabled
    }

    return $true
}
