function Test-HydrationMobileAppNameInSet {
    <#
    .SYNOPSIS
        Checks whether any supported hydration mobile app name variant exists in a name set.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]]$NameSet
    )

    foreach ($nameVariant in Get-HydrationMobileAppNameVariant -DisplayName $DisplayName) {
        if ($NameSet.Contains($nameVariant)) {
            return $true
        }
    }

    return $false
}
