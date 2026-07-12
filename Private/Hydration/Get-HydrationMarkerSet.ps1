function Get-HydrationMarkerSet {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $primaryMarker = if ($script:HydrationMarker) {
        $script:HydrationMarker
    } else {
        'Imported by Intune Hydration Kit'
    }

    $legacyMarker = if ($script:HydrationMarkerAlt) {
        $script:HydrationMarkerAlt
    } else {
        'Imported by Intune-Hydration-Kit'
    }

    return @{
        Primary = $primaryMarker
        Legacy  = $legacyMarker
        All     = @($primaryMarker, $legacyMarker) | Select-Object -Unique
    }
}
