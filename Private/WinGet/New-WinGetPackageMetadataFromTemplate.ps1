function New-WinGetPackageMetadataFromTemplate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template
    )

    if (-not $Template.PSObject.Properties.Name.Contains('resolvedPackage') -or $null -eq $Template.resolvedPackage) {
        throw "Unsupported WinGet template '$($Template.templateId)'. Open an issue requesting this app or submit a PR that adds bundled resolvedPackage metadata."
    }

    $resolvedPackage = $Template.resolvedPackage
    $match = $Template.package.match
    $manifestSource = $resolvedPackage.manifestSource
    $selectedInstaller = $resolvedPackage.selectedInstaller

    if ($null -eq $manifestSource -or $null -eq $selectedInstaller) {
        throw "WinGet template '$($Template.templateId)' resolvedPackage metadata is incomplete."
    }

    $packageVersion = [string]$resolvedPackage.packageVersion
    $packagePath = [string]$manifestSource.packagePath
    $versionPath = [string]$manifestSource.versionPath
    $repository = [string]$manifestSource.repository

    return [PSCustomObject]@{
        PackageIdentifier = [string]$Template.packageIdentifier
        PackageVersion    = $packageVersion
        PackageLocale     = [string]$match.locale
        DisplayName       = [string]$Template.displayName
        Publisher         = [string]$Template.publisher
        Description       = [string]$Template.description
        LocaleManifest    = [PSCustomObject]@{
            PackageLocale    = [string]$match.locale
            PackageName      = [string]$Template.displayName
            Publisher        = [string]$Template.publisher
            ShortDescription = [string]$Template.description
            Icons            = @()
        }
        InstallerManifest = [PSCustomObject]@{
            PackageIdentifier = [string]$Template.packageIdentifier
            PackageVersion    = $packageVersion
            InstallerType     = $selectedInstaller.InstallerType
            Installers        = @($selectedInstaller)
        }
        VersionManifest   = [PSCustomObject]@{
            PackageIdentifier = [string]$Template.packageIdentifier
            PackageVersion    = $packageVersion
        }
        ManifestPath      = $versionPath
        ManifestSource    = [PSCustomObject]@{
            Type          = 'Template'
            Repository    = $repository
            Ref           = [string]$manifestSource.ref
            PackagePath   = $packagePath
            VersionPath   = $versionPath
            InstallerFile = if ($manifestSource.installerFile) { [string]$manifestSource.installerFile } else { $null }
            LocaleFile    = if ($manifestSource.localeFile) { [string]$manifestSource.localeFile } else { $null }
        }
        Installers        = @($selectedInstaller)
        SelectedInstaller = $selectedInstaller
    }
}
