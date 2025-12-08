#Requires -Version 7.0

<#
.SYNOPSIS
    Local equivalent of the Publish Release GitHub workflow.
.DESCRIPTION
    Builds the module, creates a GitHub release, and publishes to PSGallery.
    This is the PowerShell equivalent of .github/workflows/Publish Release.yml
.PARAMETER Version
    The version to release (e.g., "0.1.8"). Must match the module manifest version.
.PARAMETER DryRun
    Perform all steps except actual publishing to PSGallery.
.PARAMETER SkipGitHubRelease
    Skip creating the GitHub release (useful for PSGallery-only publishes).
.PARAMETER PSGalleryApiKey
    The PSGallery API key. If not provided, reads from PSGALLERY_API_KEY environment variable.
.EXAMPLE
    ./scripts/Publish-Release.ps1 -Version "0.1.8"
    Creates a full release with GitHub release and PSGallery publish.
.EXAMPLE
    ./scripts/Publish-Release.ps1 -Version "0.1.8" -DryRun
    Performs all validation without actual publishing.
.EXAMPLE
    ./scripts/Publish-Release.ps1 -Version "0.2.1" -SkipGitHubRelease
    Publishes to PSGallery only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Version,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$SkipGitHubRelease,

    [Parameter()]
    [string]$PSGalleryApiKey
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Navigate to repository root
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    Write-Information "=== Publish Release (Local) ==="
    Write-Information "Version: $Version"
    Write-Information "Dry Run: $DryRun"
    Write-Information ""

    # Validate version format
    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid version format: $Version. Expected format: X.Y.Z"
    }

    # Bootstrap dependencies
    Write-Information "=== Bootstrapping Dependencies ==="
    & ./build.ps1
    Write-Information ""

    # Build the module
    Write-Information "=== Building Module ==="
    Import-Module InvokeBuild -Force
    Invoke-Build -File ./IntuneHydrationKit.build.ps1 -Task Build
    Write-Information ""

    # Validate tag matches module version
    Write-Information "=== Validating Version ==="
    $manifestPath = './IntuneHydrationKit.psd1'
    $manifestData = Import-PowerShellDataFile -Path $manifestPath
    $moduleVersion = $manifestData.ModuleVersion

    if ($moduleVersion -ne $Version) {
        throw "Requested version ($Version) does not match module manifest version ($moduleVersion). Update IntuneHydrationKit.psd1 first."
    }
    Write-Information "Version validated: $moduleVersion"
    Write-Information ""

    # Get release notes
    Write-Information "=== Release Notes ==="
    $releaseNotes = $manifestData.PrivateData.PSData.ReleaseNotes
    Write-Information $releaseNotes
    Write-Information ""

    # Create GitHub Release
    if (-not $SkipGitHubRelease) {
        Write-Information "=== Creating GitHub Release ==="

        # Check if gh CLI is available
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-Warning "GitHub CLI (gh) not found. Skipping GitHub release creation."
            Write-Warning "Install from: https://cli.github.com/"
        } else {
            # Check if tag exists
            $tagName = "v$Version"
            $existingTag = git tag -l $tagName 2>$null

            if ($DryRun) {
                Write-Information "[DRY RUN] Would create git tag: $tagName"
                Write-Information "[DRY RUN] Would create GitHub release: $tagName"
            } else {
                if (-not $existingTag) {
                    Write-Information "Creating git tag: $tagName"
                    git tag $tagName
                    git push origin $tagName
                } else {
                    Write-Information "Tag $tagName already exists"
                }

                # Create release
                $releaseBody = @"
## IntuneHydrationKit v$Version

### Installation

``````powershell
Install-Module -Name IntuneHydrationKit -Scope CurrentUser
``````

### Release Notes

$releaseNotes
"@

                Write-Information "Creating GitHub release..."
                gh release create $tagName --title "v$Version" --notes $releaseBody ./build/IntuneHydrationKit/*
                Write-Information "GitHub release created: $tagName"
            }
        }
        Write-Information ""
    }

    # Publish to PSGallery
    Write-Information "=== Publishing to PSGallery ==="

    $apiKey = $PSGalleryApiKey
    if (-not $apiKey) {
        $apiKey = $env:PSGALLERY_API_KEY
    }

    if (-not $apiKey) {
        Write-Warning "No PSGallery API key provided. Set PSGALLERY_API_KEY environment variable or use -PSGalleryApiKey parameter."
        Write-Warning "Skipping PSGallery publish."
    } else {
        $modulePath = './build/IntuneHydrationKit'

        # Validate the module before publishing
        $manifest = Test-ModuleManifest -Path (Join-Path $modulePath 'IntuneHydrationKit.psd1')
        Write-Information "Module: $($manifest.Name) v$($manifest.Version)"

        if ($DryRun) {
            Write-Information "[DRY RUN] Would publish module from: $modulePath"
        } else {
            Publish-Module -Path $modulePath -NuGetApiKey $apiKey -Verbose
            Write-Information "Successfully published to PSGallery!"
        }
    }

    Write-Information ""
    Write-Information "=== Release Complete ==="

} finally {
    Pop-Location
}
