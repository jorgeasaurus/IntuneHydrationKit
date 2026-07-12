function Get-HydrationMobileAppDisplayName {
    <#
    .SYNOPSIS
        Returns the Intune Hydration Kit display name for a mobile app.
    .DESCRIPTION
        Returns the app-name-first mobile app identification format used by
        Intune Hydration Kit. Legacy prefixed names and already-suffixed names
        are normalized so templates can safely be processed more than once.
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
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return $DisplayName
    }

    $baseName = Get-HydrationMobileAppBaseName -DisplayName $DisplayName
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        return $DisplayName
    }

    return "$baseName$suffix"
}
