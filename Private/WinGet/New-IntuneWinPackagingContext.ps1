function New-IntuneWinPackagingContext {
    <#
    .SYNOPSIS
        Creates a standardized context object for future .intunewin packaging.
    .DESCRIPTION
        Normalizes the inputs needed by a repo-owned packager so WinGet resolution,
        staging, and Intune upload code can evolve independently.
    .PARAMETER PackageMetadata
        Metadata loaded from the bundled WinGet template resolvedPackage node.
    .PARAMETER SourcePath
        Directory containing files to package.
    .PARAMETER SetupFile
        Setup file to execute from the packaged content. Defaults to the selected
        installer file name from PackageMetadata.
    .PARAMETER OutputPath
        Destination .intunewin path.
    .PARAMETER InstallCommandLine
        Command line Intune should run to install the app.
    .PARAMETER UninstallCommandLine
        Command line Intune should run to uninstall the app.
    .PARAMETER DetectionRule
        Detection rules to carry forward to Win32 app publishing.
    .PARAMETER RequirementRule
        Requirement rules to carry forward to Win32 app publishing.
    .OUTPUTS
        PSCustomObject describing a packaging request.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [PSCustomObject]$PackageMetadata,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,

        [Parameter()]
        [string]$SetupFile,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [string]$InstallCommandLine,

        [Parameter()]
        [string]$UninstallCommandLine,

        [Parameter()]
        [object[]]$DetectionRule = @(),

        [Parameter()]
        [object[]]$RequirementRule = @()
    )

    process {
        $resolvedSetupFile = if ($SetupFile) {
            $SetupFile
        } elseif ($PackageMetadata.SelectedInstaller -and $PackageMetadata.SelectedInstaller.InstallerUrl) {
            [System.IO.Path]::GetFileName(([System.Uri]$PackageMetadata.SelectedInstaller.InstallerUrl).AbsolutePath)
        } else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($resolvedSetupFile)) {
            throw 'SetupFile could not be inferred from the selected installer. Provide -SetupFile explicitly.'
        }

        $packagingCapability = Get-IntuneWinPackagingCapability
        Write-Debug "Creating WinGet packaging context for package '$($PackageMetadata.PackageIdentifier)' version '$($PackageMetadata.PackageVersion)'. SourcePath='$SourcePath', SetupFile='$resolvedSetupFile', OutputPath='$OutputPath'."
        Write-Debug "Packaging context selected installer: $(Format-WinGetInstallerSummary -Installer $PackageMetadata.SelectedInstaller)."
        Write-Debug "Packaging capability SupportsCrossPlatformIntuneWin=$($packagingCapability.SupportsCrossPlatformIntuneWin); ZipArchive=$($packagingCapability.Capabilities.ZipArchive); Aes=$($packagingCapability.Capabilities.Aes)."

        return [PSCustomObject]@{
            PackageFormat        = 'intunewin'
            Source               = 'WinGet'
            PackageIdentifier    = $PackageMetadata.PackageIdentifier
            PackageVersion       = $PackageMetadata.PackageVersion
            DisplayName          = $PackageMetadata.DisplayName
            Publisher            = $PackageMetadata.Publisher
            SourcePath           = $SourcePath
            SetupFile            = $resolvedSetupFile
            OutputPath           = $OutputPath
            InstallCommandLine   = $InstallCommandLine
            UninstallCommandLine = $UninstallCommandLine
            DetectionRule        = @($DetectionRule)
            RequirementRule      = @($RequirementRule)
            SelectedInstaller    = $PackageMetadata.SelectedInstaller
            ManifestSource       = $PackageMetadata.ManifestSource
            PackagingCapability  = $packagingCapability
        }
    }
}
