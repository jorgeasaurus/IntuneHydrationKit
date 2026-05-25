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

    foreach ($noteLine in @($Template.metadata.notes)) {
        if (-not [string]::IsNullOrWhiteSpace($noteLine)) {
            $lines.Add([string]$noteLine)
        }
    }

    foreach ($customNote in @($Template.metadata.placeholders.customNotes)) {
        if (-not [string]::IsNullOrWhiteSpace($customNote)) {
            $lines.Add([string]$customNote)
        }
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
        if (-not [string]::IsNullOrWhiteSpace($metadataLine)) {
            $lines.Add($metadataLine)
        }
    }

    return ($lines | Select-Object -Unique) -join [Environment]::NewLine
}
