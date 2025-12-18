<#
.SYNOPSIS
    Generates mobile app JSON template files for use with Import-IntuneMobileApp
.DESCRIPTION
    Creates JSON template files for various mobile app types. For winGetApp types,
    can automatically fetch app details (description, publisher, icon) from the
    Microsoft Store API using either a package identifier or search term.
.PARAMETER AppType
    The type of mobile app to create. Valid values:
    - winGetApp (Microsoft Store apps)
    - macOSMicrosoftEdgeApp
    - macOSOfficeSuiteApp
    - officeSuiteApp (Microsoft 365 Apps for Windows)
.PARAMETER SearchTerm
    For winGetApp: Search the Microsoft Store for an app by name.
    The script will display matching results and prompt for selection.
.PARAMETER PackageIdentifier
    For winGetApp: The Microsoft Store package identifier (e.g., 9WZDNCRFJ3PZ).
    If provided with -FetchFromStore, will fetch app details automatically.
.PARAMETER FetchFromStore
    For winGetApp: Automatically fetch app details (description, publisher, icon)
    from the Microsoft Store API. Requires either -SearchTerm or -PackageIdentifier.
.PARAMETER DisplayName
    The display name for the app. If -FetchFromStore is used, this is optional
    and will be fetched from the Store. Can be used to override the Store value.
.PARAMETER Description
    The app description. If -FetchFromStore is used, will be fetched from Store.
.PARAMETER Publisher
    The app publisher. If -FetchFromStore is used, will be fetched from Store.
.PARAMETER IconPath
    Optional path to a PNG/JPG image file to use as the app icon.
    If -FetchFromStore is used, the icon will be downloaded from the Store.
.PARAMETER OutputPath
    The output path for the JSON template file. Defaults to Templates/MobileApps
.PARAMETER Developer
    Optional developer name
.PARAMETER PrivacyUrl
    Optional privacy information URL. If -FetchFromStore is used, will be fetched from Store.
.PARAMETER InformationUrl
    Optional information URL. If -FetchFromStore is used, will be fetched from Store.
.PARAMETER Channel
    For macOSMicrosoftEdgeApp: The release channel (stable, beta, dev)
.PARAMETER RunAsAccount
    For winGetApp: The account to run the install as (user or system).
    If -FetchFromStore is used, will be determined from the Store manifest.
.EXAMPLE
    # Search for an app by name and create template with auto-fetched details
    .\New-MobileAppTemplate.ps1 -AppType winGetApp -SearchTerm "WhatsApp" -FetchFromStore
.EXAMPLE
    # Create template from package ID with auto-fetched details
    .\New-MobileAppTemplate.ps1 -AppType winGetApp -PackageIdentifier "9WZDNCRFJ3PZ" -FetchFromStore
.EXAMPLE
    # Manual mode - specify all details yourself
    .\New-MobileAppTemplate.ps1 -AppType winGetApp -DisplayName "Company Portal" -PackageIdentifier "9WZDNCRFJ3PZ" -Publisher "Microsoft Corporation"
.EXAMPLE
    # macOS Edge app
    .\New-MobileAppTemplate.ps1 -AppType macOSMicrosoftEdgeApp -DisplayName "Microsoft Edge" -Publisher "Microsoft" -Channel stable
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('winGetApp', 'macOSMicrosoftEdgeApp', 'macOSOfficeSuiteApp', 'officeSuiteApp')]
    [string]$AppType,

    [Parameter()]
    [string]$SearchTerm,

    [Parameter()]
    [string]$PackageIdentifier,

    [Parameter()]
    [switch]$FetchFromStore,

    [Parameter()]
    [string]$DisplayName,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [string]$Publisher,

    [Parameter()]
    [string]$IconPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$Developer,

    [Parameter()]
    [string]$PrivacyUrl,

    [Parameter()]
    [string]$InformationUrl,

    [Parameter()]
    [ValidateSet('stable', 'beta', 'dev')]
    [string]$Channel = 'stable',

    [Parameter()]
    [ValidateSet('user', 'system')]
    [string]$RunAsAccount
)

#region Parameter Validation

# Validate parameters based on mode
if ($AppType -eq 'winGetApp') {
    if ($FetchFromStore) {
        # FetchFromStore mode requires either SearchTerm or PackageIdentifier
        if (-not $SearchTerm -and -not $PackageIdentifier) {
            throw "When using -FetchFromStore, you must provide either -SearchTerm or -PackageIdentifier"
        }
    }
    else {
        # Manual mode requires DisplayName, Publisher, and PackageIdentifier
        if (-not $DisplayName) {
            throw "DisplayName is required for winGetApp when not using -FetchFromStore"
        }
        if (-not $Publisher) {
            throw "Publisher is required for winGetApp when not using -FetchFromStore"
        }
        if (-not $PackageIdentifier) {
            throw "PackageIdentifier is required for winGetApp when not using -FetchFromStore"
        }
    }
}
else {
    # Non-winGetApp types always require DisplayName and Publisher
    if (-not $DisplayName) {
        throw "DisplayName is required for $AppType"
    }
    if (-not $Publisher) {
        throw "Publisher is required for $AppType"
    }
}

#endregion

#region Helper Functions

function Search-MicrosoftStore {
    <#
    .SYNOPSIS
        Search the Microsoft Store for apps by keyword
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchTerm
    )

    $storeSearchUrl = "https://storeedgefd.dsx.mp.microsoft.com/v9.0/manifestSearch"
    $searchBody = @{
        Query = @{
            KeyWord   = $SearchTerm
            MatchType = "Substring"
        }
    } | ConvertTo-Json

    try {
        Write-Verbose "Searching Microsoft Store for: $SearchTerm"
        $response = Invoke-RestMethod -Uri $storeSearchUrl -Method POST -ContentType 'application/json' -Body $searchBody -ErrorAction Stop
        return $response.Data
    }
    catch {
        throw "Failed to search Microsoft Store: $($_.Exception.Message)"
    }
}

function Get-StoreAppManifest {
    <#
    .SYNOPSIS
        Get app manifest details from the Microsoft Store
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageIdentifier
    )

    $manifestUrl = "https://storeedgefd.dsx.mp.microsoft.com/v9.0/packageManifests/$PackageIdentifier"

    try {
        Write-Verbose "Fetching manifest for package: $PackageIdentifier"
        $response = Invoke-RestMethod -Uri $manifestUrl -Method GET -ErrorAction Stop
        return $response.Data
    }
    catch {
        throw "Failed to get app manifest: $($_.Exception.Message)"
    }
}

function Get-StoreAppDetails {
    <#
    .SYNOPSIS
        Get app details (icon, full description) from the Microsoft Store using DisplayCatalog API
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageIdentifier
    )

    $catalogUrl = "https://displaycatalog.mp.microsoft.com/v7.0/products?bigIds=$PackageIdentifier&market=US&languages=en-US"

    try {
        Write-Verbose "Fetching product details from DisplayCatalog for package: $PackageIdentifier"
        $response = Invoke-RestMethod -Uri $catalogUrl -Method GET -ErrorAction Stop

        $result = @{
            Icon = $null
            Description = $null
        }

        if ($response.Products -and $response.Products.Count -gt 0) {
            $product = $response.Products[0]
            $localizedProps = $product.LocalizedProperties[0]

            # Get the full description
            if ($localizedProps.ProductDescription) {
                $result.Description = $localizedProps.ProductDescription
            }

            # Get the icon
            $images = $localizedProps.Images | Sort-Object FileSizeInBytes -Descending

            if ($images) {
                # Find the best icon image (prefer BoxArt, fall back to Logo or Tile)
                $logoImage = $images | Where-Object { $_.ImagePurpose -eq 'BoxArt' } | Select-Object -First 1

                if (-not $logoImage) {
                    $logoImage = $images | Where-Object { $_.ImagePurpose -eq 'Logo' } | Select-Object -First 1
                }

                if (-not $logoImage) {
                    $logoImage = $images | Where-Object { $_.ImagePurpose -eq 'Tile' } | Select-Object -First 1
                }

                if ($logoImage -and $logoImage.Uri) {
                    # Ensure URL has protocol
                    $iconUrl = $logoImage.Uri
                    if ($iconUrl.StartsWith('//')) {
                        $iconUrl = "https:$iconUrl"
                    }

                    Write-Verbose "Downloading icon from: $iconUrl"
                    $webClient = New-Object System.Net.WebClient
                    $iconBytes = $webClient.DownloadData($iconUrl)
                    $iconBase64 = [Convert]::ToBase64String($iconBytes)

                    # Store images are typically PNG
                    $result.Icon = @{
                        Type  = 'image/png'
                        Value = $iconBase64
                    }
                }
            }
        }

        return $result
    }
    catch {
        Write-Warning "Failed to get app details: $($_.Exception.Message)"
        return @{
            Icon = $null
            Description = $null
        }
    }
}

# Keep old function name as alias for backward compatibility
function Get-StoreAppIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageIdentifier
    )

    $details = Get-StoreAppDetails -PackageIdentifier $PackageIdentifier
    return $details.Icon
}

#endregion

#region Main Logic

# Determine output path
if (-not $OutputPath) {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    $OutputPath = Join-Path -Path $scriptRoot -ChildPath "Templates\MobileApps"
}

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Initialize variables for store data
$storeManifest = $null
$storeAppInfo = $null
$storeInstaller = $null
$storeIcon = $null
$resolvedPackageId = $PackageIdentifier

# Handle winGetApp with FetchFromStore
if ($AppType -eq 'winGetApp' -and $FetchFromStore) {

    # Search for app if SearchTerm provided
    if ($SearchTerm) {
        Write-Host "Searching Microsoft Store for: $SearchTerm" -ForegroundColor Cyan
        $searchResults = Search-MicrosoftStore -SearchTerm $SearchTerm

        if (-not $searchResults -or $searchResults.Count -eq 0) {
            throw "No apps found matching: $SearchTerm"
        }

        # If multiple results, let user choose or use exact match
        $exactMatch = $searchResults | Where-Object { $_.PackageName -eq $SearchTerm }

        if ($exactMatch) {
            $selectedApp = $exactMatch
            Write-Host "Found exact match: $($selectedApp.PackageName)" -ForegroundColor Green
        }
        elseif ($searchResults.Count -eq 1) {
            $selectedApp = $searchResults[0]
            Write-Host "Found: $($selectedApp.PackageName)" -ForegroundColor Green
        }
        else {
            Write-Host "`nMultiple apps found:" -ForegroundColor Yellow
            for ($i = 0; $i -lt [Math]::Min($searchResults.Count, 10); $i++) {
                Write-Host "  [$($i + 1)] $($searchResults[$i].PackageName) - $($searchResults[$i].Publisher)" -ForegroundColor White
            }
            Write-Host ""

            $selection = Read-Host "Select an app (1-$([Math]::Min($searchResults.Count, 10)))"
            $selectedIndex = [int]$selection - 1

            if ($selectedIndex -lt 0 -or $selectedIndex -ge $searchResults.Count) {
                throw "Invalid selection"
            }

            $selectedApp = $searchResults[$selectedIndex]
        }

        $resolvedPackageId = $selectedApp.PackageIdentifier.ToUpper()
        Write-Host "Package Identifier: $resolvedPackageId" -ForegroundColor Gray
    }
    elseif (-not $PackageIdentifier) {
        throw "Either -SearchTerm or -PackageIdentifier is required when using -FetchFromStore"
    }
    else {
        # PackageIdentifier was provided directly, ensure uppercase
        $resolvedPackageId = $PackageIdentifier.ToUpper()
    }

    # Fetch manifest details
    Write-Host "Fetching app details from Microsoft Store..." -ForegroundColor Cyan
    $storeManifest = Get-StoreAppManifest -PackageIdentifier $resolvedPackageId

    if (-not $storeManifest) {
        throw "Failed to retrieve manifest for package: $resolvedPackageId"
    }

    # Get the latest version info
    $latestVersion = $storeManifest.Versions | Select-Object -Last 1
    $storeAppInfo = $latestVersion.DefaultLocale
    $storeInstaller = $latestVersion.Installers | Select-Object -First 1

    Write-Host "  App Name: $($storeAppInfo.PackageName)" -ForegroundColor Gray
    Write-Host "  Publisher: $($storeAppInfo.Publisher)" -ForegroundColor Gray
    Write-Host "  Version: $($latestVersion.PackageVersion)" -ForegroundColor Gray

    # Fetch full description from DisplayCatalog (and icon if not provided via -IconPath)
    if ($IconPath) {
        Write-Host "Fetching full description from DisplayCatalog..." -ForegroundColor Cyan
    } else {
        Write-Host "Fetching app icon and full description from DisplayCatalog..." -ForegroundColor Cyan
    }
    $storeDetails = Get-StoreAppDetails -PackageIdentifier $resolvedPackageId
    $storeFullDescription = $storeDetails.Description

    # Only use store icon if -IconPath was not provided
    if (-not $IconPath) {
        $storeIcon = $storeDetails.Icon
        if ($storeIcon) {
            Write-Host "  Icon: Downloaded successfully" -ForegroundColor Gray
        } else {
            Write-Warning "No icon found in store for package: $resolvedPackageId"
        }
    } else {
        Write-Host "  Icon: Using provided path" -ForegroundColor Gray
    }
    if ($storeFullDescription) {
        Write-Host "  Description: Full description retrieved" -ForegroundColor Gray
    }
}

# Build the base app body
# Use store data as defaults, allow parameter overrides
$body = [ordered]@{
    "@odata.type" = "#microsoft.graph.$AppType"
}

# Determine values - parameter overrides store data
if ($AppType -eq 'winGetApp' -and $storeAppInfo) {
    $body.displayName = if ($DisplayName) { $DisplayName } else { $storeAppInfo.PackageName }
    # Prefer full description from DisplayCatalog, fall back to ShortDescription from manifest
    $body.description = if ($PSBoundParameters.ContainsKey('Description')) {
        $Description
    } elseif ($storeFullDescription) {
        $storeFullDescription
    } else {
        $storeAppInfo.ShortDescription
    }
    $body.publisher = if ($Publisher) { $Publisher } else { $storeAppInfo.Publisher }
    $body.developer = if ($Developer) { $Developer } else { $storeAppInfo.Publisher }
    $body.informationUrl = if ($InformationUrl) { $InformationUrl } else { $storeAppInfo.PublisherSupportUrl }
    $body.privacyInformationUrl = if ($PrivacyUrl) { $PrivacyUrl } else { $storeAppInfo.PrivacyUrl }
}
else {
    $body.displayName = $DisplayName
    $body.description = if ($Description) { $Description } else { "" }
    $body.publisher = $Publisher
    $body.developer = if ($Developer) { $Developer } else { "" }
    $body.informationUrl = if ($InformationUrl) { $InformationUrl } else { "" }
    $body.privacyInformationUrl = if ($PrivacyUrl) { $PrivacyUrl } else { "" }
}

$body.isFeatured = $false
$body.categories = @()
$body.roleScopeTagIds = @()
$body.notes = ""
$body.owner = ""

# Handle icon - parameter IconPath takes precedence over store icon
if ($IconPath -and (Test-Path -Path $IconPath)) {
    $resolvedIconPath = (Resolve-Path -Path $IconPath).Path
    $iconBytes = [System.IO.File]::ReadAllBytes($resolvedIconPath)
    $iconBase64 = [Convert]::ToBase64String($iconBytes)

    $extension = [System.IO.Path]::GetExtension($IconPath).ToLower()
    $mimeType = switch ($extension) {
        '.png' { 'image/png' }
        '.jpg' { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif' { 'image/gif' }
        default { 'image/png' }
    }

    $body.largeIcon = [ordered]@{
        type  = $mimeType
        value = $iconBase64
    }
}
elseif ($storeIcon) {
    $body.largeIcon = [ordered]@{
        type  = $storeIcon.Type
        value = $storeIcon.Value
    }
}

# Add type-specific properties
switch ($AppType) {
    'winGetApp' {
        $finalPackageId = if ($resolvedPackageId) { $resolvedPackageId } else { $PackageIdentifier.ToUpper() }

        if (-not $finalPackageId) {
            throw "PackageIdentifier is required for winGetApp type"
        }

        $body.packageIdentifier = $finalPackageId
        $body.repositoryType = "microsoftStore"

        # Determine runAsAccount - parameter overrides store data
        # Store manifest uses "machine" but Intune expects "system"
        $scope = if ($RunAsAccount) {
            $RunAsAccount
        }
        elseif ($storeInstaller -and $storeInstaller.Scope) {
            # Map store scope values to Intune runAsAccount values
            switch ($storeInstaller.Scope.ToLower()) {
                'machine' { 'system' }
                'user' { 'user' }
                default { 'user' }
            }
        }
        else {
            'user'
        }

        $body.installExperience = @{
            runAsAccount = $scope
        }

        # Note: manifestHash is intentionally NOT included
        # Intune calculates and validates the manifestHash automatically
        # Including an incorrect hash causes the app to be stuck in "Processing" state
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
$safeName = $body.displayName -replace '[^\w\s-]', '' -replace '\s+', ''
$outputFile = Join-Path -Path $OutputPath -ChildPath "$safeName.json"

# Convert to JSON and save
$jsonContent = $body | ConvertTo-Json -Depth 10
$jsonContent | Out-File -FilePath $outputFile -Encoding utf8

Write-Host ""
Write-Host "Template created: $outputFile" -ForegroundColor Green
Write-Host ""
Write-Host "App Details:" -ForegroundColor Cyan
Write-Host "  Type: $AppType"
Write-Host "  Display Name: $($body.displayName)"
Write-Host "  Publisher: $($body.publisher)"
if ($body.packageIdentifier) {
    Write-Host "  Package ID: $($body.packageIdentifier)"
}
if ($body.largeIcon) {
    Write-Host "  Icon: Included"
}
if ($body.installExperience) {
    Write-Host "  Run As: $($body.installExperience.runAsAccount)"
}

return $outputFile

#endregion
