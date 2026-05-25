function New-WinGetOwnershipNotes {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template,

        [Parameter(Mandatory)]
        [psobject]$PackageMetadata
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $seenLines = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    function Add-OwnershipNoteLine {
        param(
            [Parameter()]
            [AllowNull()]
            [string]$Line
        )

        if ([string]::IsNullOrWhiteSpace($Line)) {
            return
        }

        if ($seenLines.Add($Line)) {
            $lines.Add($Line)
        }
    }

    foreach ($noteLine in @($Template.metadata.notes)) {
        Add-OwnershipNoteLine -Line ([string]$noteLine)
    }

    foreach ($customNote in @($Template.metadata.placeholders.customNotes)) {
        Add-OwnershipNoteLine -Line ([string]$customNote)
    }

    $sourceMarker = if ($Template.metadata.markers.source) {
        [string]$Template.metadata.markers.source
    } else {
        'Imported from WinGet'
    }

    foreach ($metadataLine in @(
            $sourceMarker,
            ('WinGetPackageIdentifier: {0}' -f $PackageMetadata.PackageIdentifier),
            ('WinGetPackageVersion: {0}' -f $PackageMetadata.PackageVersion),
            ('WinGetTemplateId: {0}' -f $Template.templateId),
            ('WinGetManifestRepository: {0}' -f $PackageMetadata.ManifestSource.Repository),
            ('WinGetManifestPath: {0}' -f $PackageMetadata.ManifestPath)
        )) {
        Add-OwnershipNoteLine -Line $metadataLine
    }

    return $lines -join [Environment]::NewLine
}
