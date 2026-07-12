function Get-WinGetDetectionRules {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template,

        [Parameter()]
        [psobject]$PackageMetadata
    )

    if ($Template.detection.strategy) {
        if ([string]$Template.detection.strategy -ne 'generated') {
            throw "Detection strategy '$($Template.detection.strategy)' is not supported for WinGet Win32 imports."
        }
    } elseif ($Template.detection.operator -and $Template.detection.operator -ne 'all') {
        throw "Detection operator '$($Template.detection.operator)' is not supported for WinGet Win32 imports yet."
    }

    if ($PackageMetadata -and $PackageMetadata.SelectedInstaller) {
        $installer = $PackageMetadata.SelectedInstaller
        $installerType = if ($installer.InstallerType) { $installer.InstallerType } else { '' }
        $productCode = if ($installer.ProductCode) { $installer.ProductCode } else { '' }

        if ($installerType -in @('msi', 'wix', 'burn') -and -not [string]::IsNullOrWhiteSpace($productCode)) {
            Write-Debug "Ignoring manifest ProductCode detection for '$($Template.templateId)' (Type='$installerType', ProductCode='$productCode'); generated WinGet detection is more stable across package updates."
        }
    }

    return @(
        @{
            DetectionType         = 'Script'
            ScriptFile            = 'Detect-WinGetPackage.ps1'
            EnforceSignatureCheck = $false
            RunAs32Bit            = $false
        }
    )
}
