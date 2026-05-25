function Test-IntuneWinGetAppOwnership {
    <#
    .SYNOPSIS
        Tests whether a Win32 app is owned by the WinGet hydration importer.
    .DESCRIPTION
        Requires both the standard hydration marker and the WinGet source marker or
        WinGet metadata block so delete operations only target apps created by the
        WinGet Win32 hydration flow.
    .PARAMETER Description
        App description text.
    .PARAMETER Notes
        App notes text.
    .PARAMETER ObjectName
        Optional object name for verbose logging.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Description,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Notes,

        [Parameter()]
        [string]$ObjectName
    )

    $isHydrationKitObject = Test-HydrationKitObject -Description $Description -Notes $Notes -ObjectName $ObjectName
    if (-not $isHydrationKitObject) {
        return $false
    }

    $wingetMarkers = @(
        'Imported from WinGet',
        'WinGetPackageIdentifier:'
    )

    foreach ($field in @($Description, $Notes)) {
        if ([string]::IsNullOrWhiteSpace($field)) {
            continue
        }

        foreach ($marker in $wingetMarkers) {
            if ($field -like "*$marker*") {
                if ($ObjectName) {
                    Write-Verbose "Object '$ObjectName' is owned by the WinGet hydration importer"
                }

                return $true
            }
        }
    }

    if ($ObjectName) {
        Write-Verbose "Object '$ObjectName' is not owned by the WinGet hydration importer"
    }

    return $false
}
