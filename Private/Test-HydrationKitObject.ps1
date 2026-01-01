function Test-HydrationKitObject {
    <#
    .SYNOPSIS
        Tests if an object was created by the Intune-Hydration-Kit
    .DESCRIPTION
        Checks if an object's description contains "Imported by Intune-Hydration-Kit".
        This is the standard marker used to identify objects created by this module.
    .PARAMETER Description
        The description field of the object to check
    .PARAMETER ObjectName
        Optional. The name of the object (for logging purposes)
    .EXAMPLE
        if (Test-HydrationKitObject -Description $policy.description) {
            # Safe to delete - created by this kit
        }
    .EXAMPLE
        Test-HydrationKitObject -Description "Some policy - Imported by Intune-Hydration-Kit"
        # Returns: $true
    .EXAMPLE
        Test-HydrationKitObject -Description "Manually created policy"
        # Returns: $false
    .OUTPUTS
        System.Boolean - $true if the object was created by Intune-Hydration-Kit, $false otherwise
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Description,

        [Parameter()]
        [string]$ObjectName
    )

    # The marker that identifies objects created by this kit
    $hydrationMarker = "Imported by Intune-Hydration-Kit"

    # Also check for alternate format (space vs hyphen variations)
    $alternateMarker = "Imported by Intune Hydration Kit"

    if ([string]::IsNullOrWhiteSpace($Description)) {
        if ($ObjectName) {
            Write-Verbose "Object '$ObjectName' has no description - not a Hydration Kit object"
        }
        return $false
    }

    $isHydrationKit = ($Description -like "*$hydrationMarker*") -or ($Description -like "*$alternateMarker*")

    if ($ObjectName) {
        if ($isHydrationKit) {
            Write-Verbose "Object '$ObjectName' is a Hydration Kit object (marker found in description)"
        }
        else {
            Write-Verbose "Object '$ObjectName' is NOT a Hydration Kit object (no marker in description)"
        }
    }

    return $isHydrationKit
}
