function Test-HydrationKitObject {
    <#
    .SYNOPSIS
        Tests if an object was created by the Intune Hydration Kit
    .DESCRIPTION
        Checks if an object's description or notes field contains "Imported by Intune Hydration Kit".
        This is the standard marker used to identify objects created by this module.
        Some Graph API resources use 'description', some use 'notes', and some support both.
        Pass whichever fields are available — returns $true if either contains the marker.
    .PARAMETER Description
        The description field of the object to check
    .PARAMETER Notes
        The notes field of the object to check (used by mobile apps and some other resource types)
    .PARAMETER ObjectName
        Optional. The name of the object (for logging purposes)
    .EXAMPLE
        if (Test-HydrationKitObject -Description $policy.description) {
            # Safe to delete - created by this kit
        }
    .EXAMPLE
        Test-HydrationKitObject -Description "Some policy - Imported by Intune Hydration Kit"
        # Returns: $true
    .EXAMPLE
        Test-HydrationKitObject -Notes "Imported by Intune Hydration Kit"
        # Returns: $true
    .EXAMPLE
        Test-HydrationKitObject -Description "Manually created" -Notes "Admin notes"
        # Returns: $false
    .OUTPUTS
        System.Boolean - $true if the object was created by Intune Hydration Kit, $false otherwise
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Notes,

        [Parameter()]
        [string]$ObjectName
    )

    $markers = (Get-HydrationMarkerSet).All

    $fieldsToCheck = @($Description, $Notes)
    $isHydrationKit = $false

    foreach ($field in $fieldsToCheck) {
        if (-not [string]::IsNullOrWhiteSpace($field)) {
            foreach ($marker in $markers) {
                if ($field -like "*$marker*") {
                    $isHydrationKit = $true
                    break
                }
            }

            if ($isHydrationKit) {
                break
            }
        }
    }

    if ($ObjectName) {
        if ($isHydrationKit) {
            Write-Verbose "Object '$ObjectName' is a Hydration Kit object (marker found)"
        } elseif ([string]::IsNullOrWhiteSpace($Description) -and [string]::IsNullOrWhiteSpace($Notes)) {
            Write-Verbose "Object '$ObjectName' has no description or notes - not a Hydration Kit object"
        } else {
            Write-Verbose "Object '$ObjectName' is NOT a Hydration Kit object (no marker found)"
        }
    }

    return $isHydrationKit
}
