function Add-HydrationDryRunResult {
    <#
    .SYNOPSIS
        Logs a dry-run action and returns a standardized hydration result.
    .DESCRIPTION
        Centralizes WhatIf output handling by emitting a consistent log message and
        returning a New-HydrationResult object with Status='DryRun'.
    .PARAMETER Action
        Dry-run action to record. Valid values: WouldCreate, WouldUpdate, WouldDelete.
    .PARAMETER Name
        Resource display name.
    .PARAMETER Type
        Resource type label for the result object.
    .PARAMETER Path
        Optional template or source path.
    .PARAMETER Id
        Optional existing resource identifier.
    .PARAMETER Platform
        Optional platform label (Windows, macOS, iOS, Android, Linux).
    .PARAMETER State
        Optional resource state label.
    .EXAMPLE
        Add-HydrationDryRunResult -Action WouldDelete -Name '[IHD] Baseline Policy' -Type 'CompliancePolicy'
    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('WouldCreate', 'WouldUpdate', 'WouldDelete')]
        [string]$Action,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$Type,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [string]$Id,

        [Parameter()]
        [string]$Platform,

        [Parameter()]
        [string]$State
    )

    Write-HydrationLog -Message "  ${Action}: $Name" -Level Info
    return New-HydrationResult -Name $Name -Path $Path -Type $Type -Action $Action -Status 'DryRun' -Id $Id -Platform $Platform -State $State
}