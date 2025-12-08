<#
.SYNOPSIS
    Generates mobile app JSON template files for use with Import-IntuneMobileApp
.DESCRIPTION
    Creates JSON template files for various mobile app types by gathering app details
    and optionally including icon images encoded as base64.
.PARAMETER AppType
    The type of mobile app to create. Valid values:
    - winGetApp (Microsoft Store apps)
    - macOSMicrosoftEdgeApp
    - macOSOfficeSuiteApp
    - officeSuiteApp (Microsoft 365 Apps for Windows)
.PARAMETER DisplayName
    The display name for the app
.PARAMETER Description
    The app description
.PARAMETER Publisher
    The app publisher
.PARAMETER PackageIdentifier
    For winGetApp: The Microsoft Store package identifier (e.g., 9WZDNCRFJ3PZ)
.PARAMETER IconPath
    Optional path to a PNG image file to use as the app icon
.PARAMETER OutputPath
    The output path for the JSON template file. Defaults to Templates/MobileApps
.PARAMETER Developer
    Optional developer name
.PARAMETER PrivacyUrl
    Optional privacy information URL
.PARAMETER InformationUrl
    Optional information URL
.PARAMETER Channel
    For macOSMicrosoftEdgeApp: The release channel (stable, beta, dev)
.PARAMETER RunAsAccount
    For winGetApp: The account to run the install as (user or system)
.EXAMPLE
    .\New-MobileAppTemplate.ps1 -AppType winGetApp -DisplayName "Company Portal" -PackageIdentifier "9WZDNCRFJ3PZ" -Publisher "Microsoft Corporation"
.EXAMPLE
    .\New-MobileAppTemplate.ps1 -AppType winGetApp -DisplayName "PowerShell" -PackageIdentifier "9MZ1SNWT0N5D" -Publisher "Microsoft Corporation" -IconPath ".\powershell.png"
.EXAMPLE
    .\New-MobileAppTemplate.ps1 -AppType macOSMicrosoftEdgeApp -DisplayName "Microsoft Edge for macOS" -Publisher "Microsoft" -Channel stable
.EXAMPLE
    .\Scripts\New-MobileAppTemplate.ps1 -AppType winGetApp `
        -DisplayName "Adobe Acrobat Reader" `
        -Description $Description `
        -PackageIdentifier "XPDP273C0XHQH2" `
        -Publisher "ADOBE INC." `
        -PrivacyUrl "https://www.adobe.com/privacy/policy-linkfree.html" `
        -IconPath ".\Templates\MobileApps\Adobe.png"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('winGetApp', 'macOSMicrosoftEdgeApp', 'macOSOfficeSuiteApp', 'officeSuiteApp')]
    [string]$AppType,

    [Parameter(Mandatory)]
    [string]$DisplayName,

    [Parameter()]
    [string]$Description = "",

    [Parameter(Mandatory)]
    [string]$Publisher,

    [Parameter()]
    [string]$PackageIdentifier,

    [Parameter()]
    [string]$IconPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$Developer = "",

    [Parameter()]
    [string]$PrivacyUrl = "",

    [Parameter()]
    [string]$InformationUrl = "",

    [Parameter()]
    [ValidateSet('stable', 'beta', 'dev')]
    [string]$Channel = 'stable',

    [Parameter()]
    [ValidateSet('user', 'system')]
    [string]$RunAsAccount = 'user'
)

# Determine output path
if (-not $OutputPath) {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    $OutputPath = Join-Path -Path $scriptRoot -ChildPath "Templates\MobileApps"
}

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Build the base app body
$body = [ordered]@{
    "@odata.type"         = "#microsoft.graph.$AppType"
    displayName           = $DisplayName
    description           = $Description
    publisher             = $Publisher
    developer             = $Developer
    informationUrl        = $InformationUrl
    privacyInformationUrl = $PrivacyUrl
    isFeatured            = $false
    categories            = @()
    roleScopeTagIds       = @()
    notes                 = ""
    owner                 = ""
}

# Add icon if provided
if ($IconPath -and (Test-Path -Path $IconPath)) {
    $iconBytes = [System.IO.File]::ReadAllBytes($IconPath)
    $iconBase64 = [convert]::ToBase64String($iconBytes)

    # Determine image type from extension
    $extension = [System.IO.Path]::GetExtension($IconPath).ToLower()
    $mimeType = switch ($extension) {
        '.png' { 'image/png' }
        '.jpg' { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif' { 'image/gif' }
        default { 'image/png' }
    }

    $body.largeIcon = [ordered]@{
        "@odata.type" = "#microsoft.graph.mimeContent"
        type          = $mimeType
        value         = $iconBase64
    }
}

# Add type-specific properties
switch ($AppType) {
    'winGetApp' {
        if (-not $PackageIdentifier) {
            throw "PackageIdentifier is required for winGetApp type"
        }
        $body.packageIdentifier = $PackageIdentifier
        $body.repositoryType = "microsoftStore"
        $body.installExperience = @{
            runAsAccount = $RunAsAccount
        }
    }
    'macOSMicrosoftEdgeApp' {
        $body.channel = $Channel
    }
    'macOSOfficeSuiteApp' {
        # No additional properties needed
    }
    'officeSuiteApp' {
        $body.autoAcceptEula = $true
        $body.excludedApps = @{
            lync               = $true
            infoPath           = $true
            sharePointDesigner = $true
            groove             = $true
        }
        $body.officePlatformArchitecture = "x64"
        $body.localesToInstall = @()
        $body.productIds = @("o365ProPlusRetail")
        $body.shouldUninstallOlderVersionsOfOffice = $true
        $body.targetVersion = ""
        $body.updateChannel = "monthlyEnterprise"
        $body.updateVersion = ""
        $body.useSharedComputerActivation = $false
        $body.officeSuiteAppDefaultFileFormat = "OfficeOpenDocumentFormat"
    }
}

# Generate filename from display name
$safeName = $DisplayName -replace '[^\w\s-]', '' -replace '\s+', ''
$outputFile = Join-Path -Path $OutputPath -ChildPath "$safeName.json"

# Convert to JSON and save
$jsonContent = $body | ConvertTo-Json -Depth 10
$jsonContent | Out-File -FilePath $outputFile -Encoding utf8

Write-Host "Template created: $outputFile" -ForegroundColor Green
Write-Host ""
Write-Host "App Details:" -ForegroundColor Cyan
Write-Host "  Type: $AppType"
Write-Host "  Display Name: $DisplayName"
Write-Host "  Publisher: $Publisher"
if ($PackageIdentifier) {
    Write-Host "  Package ID: $PackageIdentifier"
}
if ($IconPath) {
    Write-Host "  Icon: Included"
}

return $outputFile
