function Get-HydrationMobileAppExistingMatch {
    <#
    .SYNOPSIS
        Finds an existing mobile app by any supported hydration name variant.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ExistingApps,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DisplayName,

        [Parameter()]
        [ValidateSet('IsTagged', 'IsOwned')]
        [string]$OwnershipProperty = 'IsTagged'
    )

    foreach ($nameVariant in Get-HydrationMobileAppNameVariant -DisplayName $DisplayName) {
        if (-not $ExistingApps.ContainsKey($nameVariant)) {
            continue
        }

        $existingApp = $ExistingApps[$nameVariant]
        $ownershipState = if ($existingApp -is [hashtable]) {
            $existingApp[$OwnershipProperty]
        } else {
            $property = $existingApp.PSObject.Properties[$OwnershipProperty]
            if ($property) { $property.Value } else { $false }
        }

        if ($ownershipState) {
            return $nameVariant
        }
    }

    return $null
}
