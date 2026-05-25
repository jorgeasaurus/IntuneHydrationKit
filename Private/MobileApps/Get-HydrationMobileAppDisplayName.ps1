function Get-HydrationMobileAppDisplayName {
    <#
    .SYNOPSIS
        Returns the Intune Hydration Kit display name for a mobile app.
    .DESCRIPTION
        Appends the mobile app identification suffix used by Intune Hydration Kit.
        Existing suffixed names are returned unchanged so templates can safely be
        processed more than once.
    .PARAMETER DisplayName
        The template display name to format.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DisplayName
    )

    $suffix = ' - [IHD]'
    if ([string]::IsNullOrWhiteSpace($DisplayName) -or $DisplayName.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $DisplayName
    }

    return "$DisplayName$suffix"
}
