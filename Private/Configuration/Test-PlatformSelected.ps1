function Test-PlatformSelected {
    <#
    .SYNOPSIS
        Tests whether a specific platform is included in the selected platforms list.
    .DESCRIPTION
        Returns true if the platform list contains 'All' or the specific platform name.
    .PARAMETER SelectedPlatforms
        Array of platform names selected for the hydration run.
    .PARAMETER PlatformName
        The platform name to test for (e.g., 'Windows', 'macOS').
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$SelectedPlatforms,

        [Parameter(Mandatory)]
        [string]$PlatformName
    )

    return $SelectedPlatforms -contains 'All' -or $SelectedPlatforms -contains $PlatformName
}
