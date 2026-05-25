# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Intune Hydration Kit is a PowerShell module that bootstraps Microsoft Intune tenants with best-practice defaults. It hydrates tenants with:
- OpenIntuneBaseline policies (99 bundled JSON templates - no external download required)
- CIS Baselines (728 bundled benchmark-derived policies)
- Compliance Baseline Pack (10 multi-platform policies)
- Enrollment Profiles (Autopilot, Self-Deploy, ESP, macOS DEP, Device Preparation)
- Dynamic Group Suite (50 groups) and Static Groups (5 groups)
- Device Filters (24 platform, manufacturer, and VM filters)
- App Protection Policies (8 MAM policies + 2 BYOD baseline policies)
- Notification Templates
- Mobile Apps (8 legacy templates plus 28 WinGet Win32 app templates)
- Conditional Access Starter Pack (21 policies, all disabled by default)

Uses Microsoft Graph API via `Invoke-MgGraphRequest` (only `Microsoft.Graph.Authentication` module required). Most resources are prefixed with `[IHD] ` for instant identification; mobile apps and WinGet apps append ` - [IHD]`. Created objects are tagged with a hydration kit marker for safe deletion.

## Build and Test Commands

### InvokeBuild System (Primary)

```powershell
# Bootstrap build environment and run default tasks (Analyze + Test + Build)
./build.ps1

# Run PSScriptAnalyzer linting only
./build.ps1 -Task Analyze

# Run Pester tests only
./build.ps1 -Task Test

# Build module to build/IntuneHydrationKit/
./build.ps1 -Task Build

# CI task - full validation without publishing (Analyze + Test + Build)
./build.ps1 -Task CI

# Clean build artifacts
./build.ps1 -Task Clean
```

### Direct Commands

```powershell
# Run all Pester tests
Invoke-Pester -Path ./Tests -Output Detailed

# Run a single test file
Invoke-Pester -Path ./Tests/Public/Connect-IntuneHydration.Tests.ps1 -Output Detailed

# Lint with ScriptAnalyzer
Invoke-ScriptAnalyzer -Path . -Recurse

# Import the module locally for development
Import-Module ./IntuneHydrationKit.psd1 -Force
```

### Running the Module

```powershell
# Setup: Copy and configure settings (schema at settings.schema.json)
Copy-Item settings.example.json settings.json
# Edit settings.json with your tenant details

# Dry-run mode (validates without writing to Graph)
pwsh ./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -WhatIf

# Live run with force update
pwsh ./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -Force

# Parameter-based invocation (no settings file)
Invoke-IntuneHydration -TenantId "guid" -Interactive -Create -All -WhatIf

# Delete all hydration kit resources then recreate
Invoke-IntuneHydration -Interactive -Delete -TenantId "guid" -All -Force
Invoke-IntuneHydration -Interactive -Create -TenantId "guid" -All
```

## Architecture

### Entry Point

- `Invoke-IntuneHydration.ps1` - Wrapper script (backward compatibility for cloned repo)
- `Public/Orchestration/Invoke-IntuneHydration.ps1` - Main orchestrator function (used when installed from PSGallery)

### Module Structure

- `IntuneHydrationKit.psd1` / `IntuneHydrationKit.psm1` - Module manifest and loader (dot-sources Public/Private)
- `Public/` - 19 exported public functions (one file per function)
- `Private/` - 95 internal helper functions

### Module-Level State

The module maintains state in script-scoped variables (defined in `IntuneHydrationKit.psm1`):
- `$script:HydrationState` - Tracks connection status, tenant ID, and results (Groups, Policies, Baselines, Profiles, ConditionalAccess, Errors, Warnings)
- `$script:LogPath`, `$script:CurrentLogFile`, `$script:VerboseLogging` - Logging state
- `$script:GraphEnvironment`, `$script:GraphEndpoint` - Graph API configuration
- `$script:ImportPrefix` - Resource naming prefix, defaults to `'[IHD] '`
- `$script:MaxBatchSize` - Batch API item limit per request, defaults to `10` (Graph max is 20)
- `$script:TemplatesPath` - Path to Templates directory

### Templates Directory

All JSON templates for import operations:

- `Templates/OpenIntuneBaseline/` - Bundled baseline security policies (OS/PolicyType/policy.json structure)
- `Templates/Compliance/` - Platform compliance policies (Windows, iOS, macOS, Android, Linux)
- `Templates/Enrollment/` - Autopilot, ESP, macOS DEP, and Device Preparation profiles
- `Templates/DynamicGroups/` - OS, Manufacturer, and Autopilot group definitions
- `Templates/StaticGroups/` - Assigned groups (Update Ring Pilot, UAT)
- `Templates/Filters/` - Device filter definitions
- `Templates/ConditionalAccess/` - CA starter pack (forced disabled on import)
- `Templates/AppProtection/` - Android and iOS MAM policy templates
- `Templates/MobileApps/` - macOS, Microsoft Store/M365 fallback, and Windows WinGet app templates
- WinGet app imports are limited to bundled templates. New apps should be requested by issue or added by PR with template metadata.
- `Templates/Notifications/` - Notification message templates

### Build System

- `build.ps1` - Bootstrap script that installs InvokeBuild and runs tasks
- `IntuneHydrationKit.build.ps1` - InvokeBuild task definitions (Analyze, Test, Build)
- `scripts/New-MobileAppTemplate.ps1` - Generate mobile app JSON templates
- `scripts/Compare-OpenIntuneBaseline.ps1` - Compare baseline versions
- `scripts/Export-ConditionalAccessTemplates.ps1` - Export CA templates from tenant
- `scripts/Format-AllFiles.ps1` - Code formatting utility
- `scripts/Set-AllAppsRequiredOnAllDevices.ps1` - Assign apps as required for all devices
- `scripts/Set-WindowsAppsAvailableToAllUsers.ps1` - Assign Windows apps as available for all users

### Test Structure

Tests mirror the module structure (64 test files, 860+ tests):
- `Tests/Public/` - 19 test files for public functions
- `Tests/Private/` - 45 test files for private helper functions

### Output

- `Reports/Hydration-Summary.md` and `.json` - Generated run summary with counts, IDs, errors
- `Logs/` - Detailed execution logs
- `build/` - Build artifacts (generated by `./build.ps1 -Task Build`)

## Execution Flow

The orchestrator (`Invoke-IntuneHydration`) runs 12 steps:

1. Authenticate via `Connect-MgGraph` with required scopes
2. Run pre-flight checks (Intune license, MDM authority)
3. Create/delete dynamic groups (batch operations via `Invoke-GroupBatchImport`)
3b. Create/delete static groups
4. Import/delete device filters
5. Import/delete OpenIntuneBaseline policies (routed by `@odata.type` or folder name)
6. Import/delete compliance templates
7. Import/delete notification templates
8. Import/delete app protection policies (MAM)
9. Import/delete enrollment profiles (Autopilot, ESP, DEP, Device Prep)
10. Import/delete conditional access starter pack (CA policies always disabled on import)
11. Import/delete mobile apps
12. Generate summary report

## Batch API Architecture

Graph API calls use batch operations for performance (~61% faster than sequential):

- `Invoke-GraphBatchOperation` - Centralized batch executor for POST/DELETE operations
  - Batches up to `$script:MaxBatchSize` (10) items per request
  - Retry with exponential backoff for 429 (throttle), 500+, 503 errors
  - Tracks seen response indices to detect missing batch responses
  - Items can specify custom URLs or inherit from `BaseUrl` parameter
  - POST bodies sent as JSON strings to avoid PowerShell serialization issues
- `Invoke-GroupBatchImport` - Group-specific batch handler (existence check → create/delete)
  - Two-phase creation: batch existence checks, then batch creation
  - Template-scoped deletion: requires both kit marker AND matching template name

## Baseline Import Routing

`Import-IntuneBaseline` uses two routing strategies based on folder structure:

- **IntuneManagement path** (`$intuneManagementFolders`): Routes by `@odata.type` via `$odataTypeToEndpoint` map. Used for `IntuneManagement/` and `AppProtection/` subfolders.
- **Non-IntuneManagement path** (`$endpointMap`): Routes by folder name to Graph endpoint. Used for legacy folder structures.
- **Delete path**: Platform-scoped `$deleteEndpoints` - shared endpoints always included, platform-specific endpoints (WUfB drivers, app protection) only when that platform is in scope.

## Key Graph Scopes Required

```powershell
"DeviceManagementConfiguration.ReadWrite.All",
"DeviceManagementServiceConfig.ReadWrite.All",
"DeviceManagementManagedDevices.ReadWrite.All",
"DeviceManagementScripts.ReadWrite.All",
"DeviceManagementApps.ReadWrite.All",
"Group.ReadWrite.All",
"Policy.Read.All",
"Policy.ReadWrite.ConditionalAccess",
"Application.Read.All",
"Directory.ReadWrite.All",
"LicenseAssignment.Read.All",
"Organization.Read.All"
```

## Exported Functions

Key module functions for hydration operations:

- `Invoke-IntuneHydration` - Main entry point for full hydration run
- `Connect-IntuneHydration` - Authenticate to Graph
- `Test-IntunePrerequisites` - Pre-flight license/MDM checks
- `New-IntuneDynamicGroup` - Create dynamic Azure AD groups
- `New-IntuneStaticGroup` - Create static Azure AD groups
- `Get-OpenIntuneBaseline` - Download upstream baseline from GitHub
- `Import-IntuneBaseline` - Import OpenIntuneBaseline policies
- `Import-IntuneCompliancePolicy` - Import compliance templates
- `Import-IntuneAppProtectionPolicy` - Import MAM policies
- `Import-IntuneNotificationTemplate` - Import notification templates
- `Import-IntuneEnrollmentProfile` - Import Autopilot/ESP/DEP/Device Prep profiles
- `Import-IntuneDeviceFilter` - Import device filters
- `Import-IntuneConditionalAccessPolicy` - Import CA policies (always disabled)
- `Import-IntuneMobileApp` - Import mobile applications
- `Import-IntuneWinGetApp` - Import WinGet-backed Windows Win32 applications

Helper functions (Public):

- `Initialize-HydrationLogging` - Set up logging for hydration run
- `Write-HydrationLog` - Write log entries
- `Import-HydrationSettings` - Load settings from JSON file

Private helper functions:

- `Invoke-GraphBatchOperation` - Centralized batch Graph API executor with retry
- `Invoke-GroupBatchImport` - Group-specific batch import with existence checks
- `Get-GraphPagedResults` - Paginated Graph API list helper
- `Get-FilteredTemplates` - Load and filter JSON templates by platform/suffix
- `Get-TemplateDisplayNames` - Extract display names from template files (returns HashSet)
- `New-HydrationResult` - Create standardized result objects
- `New-HydrationDescription` - Generate/append hydration kit marker to descriptions
- `Get-GraphErrorMessage` - Extract human-readable errors from Graph API responses
- `Get-ResultSummary` - Generate summary statistics from results
- `Remove-ReadOnlyGraphProperties` - Strip read-only properties before POST/PATCH
- `Copy-DeepObject` - Deep clone objects to avoid reference issues
- `Test-HydrationKitObject` - Check if object was created by this kit (via description marker)
- `Get-ObfuscatedTenantId` - Obfuscate tenant ID for logging
- `Test-WindowsDriverUpdateLicense` - Pre-check for Windows E3/E5 license for driver updates
- `Get-PremiumP2ServicePlans` - Check for Azure AD Premium P2 license
- `Test-ConditionalAccessPolicyRequiresP2` - Detect CA policies needing P2 license
- `Test-ConditionalAccessPolicyRequiresPreview` - Detect CA policies needing preview features
- `Get-HydrationTemplates` - Load JSON templates from Templates directory

## Dependencies

- Microsoft.Graph.Authentication v2.0.0+ - Only module required at runtime (uses `Invoke-MgGraphRequest`)
- PowerShell 7.0+
- Pester 5.x (for testing)
- PSScriptAnalyzer (for linting)
- InvokeBuild (for build system, installed automatically by `build.ps1`)

## Design Principles

- **Idempotent**: Create-or-update behavior; safe to run multiple times
- **Dry-run support**: WhatIf mode validates without writing to Graph
- **Batch operations**: Up to 10 items per Graph API batch request for performance
- **Retry logic**: Exponential backoff for 429 (throttle), 500+, 503 errors
- **[IHD] naming**: Most created resources use the `[IHD] ` prefix; mobile apps and WinGet apps append ` - [IHD]`
- **Hydration marker**: All objects tagged with "Imported by Intune Hydration Kit" in description
- **Template-scoped deletes**: Only deletes objects with BOTH the hydration marker AND a matching template name
- **Dual-lookup idempotency**: Importers check for both prefixed (`[IHD] Name`) and legacy unprefixed (`Name`) to prevent duplicates
- **Platform filtering**: `-Platform` parameter scopes both create and delete to specific OS platforms
- **All CA policies disabled**: Conditional Access imports always forced to disabled state
- **Test mode**: Import only first item of each type for validation

## Important Notes

- Custom Windows compliance templates contain placeholders (`REPLACE_SCRIPT_ID`, `REPLACE_RULES_BASE64`) that must be replaced before use
- OpenIntuneBaseline templates are bundled in `Templates/OpenIntuneBaseline/` (can also download dynamically via `Get-OpenIntuneBaseline`)
- Always review Conditional Access policies before enabling in production
- Uses beta Graph API endpoints for certain Intune resources
- CI/CD pipeline runs tests on Windows, macOS, and Linux
- `managedAppPolicies` is a read-only aggregation endpoint - app protection creates/deletes use type-specific endpoints (`androidManagedAppProtections`, `iosManagedAppProtections`)
- Linux compliance policies use `name` property instead of `displayName`
- Graph batch responses use string IDs (1-indexed) - always use `[int]::TryParse()` for safe parsing
- When running delete then create, always run DELETE first to clean up legacy resources

## Code Style

Follow the guidelines in `.github/instructions/`:
- `powershell.instructions.md` - PowerShell cmdlet development best practices
- `powershell-pester-5.instructions.md` - Pester v5 testing conventions

PSScriptAnalyzer rules excluded in build (see `IntuneHydrationKit.build.ps1`):

- `PSUseShouldProcessForStateChangingFunctions` - Handled manually in this codebase
- `PSAvoidUsingConvertToSecureStringWithPlainText` - Required for settings file workflow
