# IntuneHydrationKit - Copilot Instructions

## Project Overview

Intune Hydration Kit is a PowerShell 7 module that bootstraps Microsoft Intune tenants with best-practice baseline configurations. It uses `Invoke-MgGraphRequest` (only `Microsoft.Graph.Authentication` required) to import policies, groups, compliance baselines, enrollment profiles, conditional access, mobile apps, and device filters. If required Graph scopes are missing, instruct the user to grant the missing permissions and stop the operation.

## Build, Test, and Lint

Use the InvokeBuild-based bootstrap script (installs dependencies automatically):

```powershell
# Full CI pipeline: Analyze + Test + Build
./build.ps1 -Task CI

# Run specific tasks
./build.ps1 -Task Analyze          # PSScriptAnalyzer only
./build.ps1 -Task Test             # Pester tests only
./build.ps1 -Task Build            # Build module to build/IntuneHydrationKit/
./build.ps1 -Task Clean            # Remove build artifacts

# Direct commands (module must be imported first for tests)
Import-Module ./IntuneHydrationKit.psd1 -Force
Invoke-Pester -Path ./Tests/Private/Invoke-GraphBatchOperation.Tests.ps1 -Output Detailed
Invoke-ScriptAnalyzer -Path ./Public/Orchestration/Invoke-IntuneHydration.ps1
```

PSScriptAnalyzer excludes `PSUseShouldProcessForStateChangingFunctions` and `PSAvoidUsingConvertToSecureStringWithPlainText` (handled manually).

## High-Level Architecture

### Module Structure
- `IntuneHydrationKit.psm1` - Root module. Defines `$script:` state variables and dot-sources `Public/**/*.ps1` and `Private/**/*.ps1`.
- `Public/` - 19 exported functions (one file per function). Main entry point: `Invoke-IntuneHydration`.
- `Private/` - Internal helpers (batch operations, pagination, template loading, result formatting, auth).
- `Templates/` - JSON templates organized by resource type (OpenIntuneBaseline, Compliance, Enrollment, DynamicGroups, StaticGroups, Filters, ConditionalAccess, AppProtection, MobileApps, Notifications).

### Execution Flow (`Invoke-IntuneHydration`)
High-level flow: authenticate and validate prerequisites, process template-driven imports/deletes by resource type, then generate reports.
Runs 12 sequential steps:
1. Authenticate via `Connect-MgGraph`
2. Pre-flight checks (`Test-IntunePrerequisites`) - Intune license, MDM authority
3. Create/delete dynamic groups (`Invoke-GroupBatchImport`)
3b. Create/delete static groups
4. Import/delete device filters
5. Import/delete OpenIntuneBaseline policies (routed by `@odata.type` or folder name)
6. Import/delete compliance templates
7. Import/delete notification templates
8. Import/delete app protection policies (MAM)
9. Import/delete enrollment profiles (Autopilot, ESP, DEP, Device Prep)
10. Import/delete conditional access policies (always disabled on import)
11. Import/delete mobile apps
12. Generate summary report (`Reports/Hydration-Summary.md` + `.json`)

### State & Configuration
- `$script:HydrationState` - connection status, tenant ID, results (Groups, Policies, Baselines, Profiles, ConditionalAccess, Errors, Warnings)
- `$script:ImportPrefix = '[IHD] '` - prepended to most resource display names; mobile apps and WinGet apps append ` - [IHD]`
- `$script:HydrationMarker` / `$script:HydrationMarkerAlt` - description marker for safe deletion
- Settings file: `settings.json` (validated against `settings.schema.json`)

## Key Conventions

### One File Per Function
Every function lives in its own `.ps1` file named exactly after the function. Public functions are exported in both the `.psd1` manifest and the `.psm1` `$publicFunctions` array. Keep them in sync.

### Graph API Batch Pattern
All imports/deletions that touch Graph use `Invoke-GraphBatchOperation`:
- Batches up to `$script:MaxBatchSize` (default 10) items per request
- Retry with exponential backoff for 429 (throttle), 500+, 503
- POST bodies are sent as raw JSON strings (not hashtables) to avoid PowerShell serialization issues
- DELETE items need `Id`; POST items need `BodyJson`
- Batch responses use string IDs (1-indexed) - always parse with `[int]::TryParse()`

### Idempotency & Dual-Lookup
Importers check for both prefixed (`[IHD] Name`) and legacy unprefixed (`Name`) display names before creating, to prevent duplicates across runs.

### Template-Scoped Deletion
Delete operations only remove objects that have BOTH the hydration marker in their description AND a matching template name. If only one condition is met, the object is not deleted. This prevents accidental deletion of manually created resources.

### Baseline Import Routing (`Import-IntuneBaseline`)
Uses two routing strategies:
- **IntuneManagement path** (`$intuneManagementFolders`): Routes by `@odata.type` via `$odataTypeToEndpoint` map. Used for `IntuneManagement/` and `AppProtection/` subfolders.
- **Non-IntuneManagement path** (`$endpointMap`): Routes by folder name to Graph endpoint. Used for legacy folder structures.
- **Delete path**: Platform-scoped `$deleteEndpoints` - shared endpoints always included, platform-specific endpoints (WUfB drivers, app protection) only when that platform is in scope.

### Platform Filtering
`-Platform` parameter (valid: Windows, macOS, iOS, Android, Linux, All) scopes both create and delete operations.
Apply filtering in this order:
1. `Folder` for OpenIntuneBaseline uppercase folders (`WINDOWS`, `MACOS`, `BYOD`)
2. `Directory` for parent-directory scoped templates
3. `Prefix` for filename prefixes (e.g., `Windows-*`, `macOS-*`)
4. `Suffix` for filename suffixes (e.g., `*-iOS.json`)

### Resource Naming
- Most created resources: displayName prefixed with `[IHD] `
- Mobile apps and WinGet apps: displayName suffixed with ` - [IHD]`
- All created objects: description includes hydration marker for identification and safe deletion
- Linux compliance policies use `name` property instead of `displayName`
- `managedAppPolicies` is a read-only aggregation endpoint - app protection creates/deletes use type-specific endpoints (`androidManagedAppProtections`, `iosManagedAppProtections`)

### Conditional Access
All CA policies are imported with state forced to `disabled`. They must be manually reviewed and enabled in production.

### WhatIf / Dry-Run Support
`-WhatIf` validates settings and templates without writing to Graph. The orchestrator branches on `$PSCmdlet.ShouldProcess()` and manual `$WhatIfPreference` checks.

### Error Handling Pattern
- Advanced functions use `[CmdletBinding()]`
- For non-terminating errors inside advanced functions, prefer `$PSCmdlet.WriteError()` over `Write-Error`
- For terminating errors, prefer `$PSCmdlet.ThrowTerminatingError()` over `throw`
- Always construct proper `ErrorRecord` objects with category, target, and exception details

### Testing
- Pester v5 with `BeforeAll`, `Describe`, `Context`, `It`
- Test files mirror module structure: `Tests/Public/` and `Tests/Private/` (64 test files, 860+ tests)
- Use `Mock` for external dependencies (e.g., `Invoke-MgGraphRequest`)
- Import the module in test `BeforeAll` blocks with `Import-Module ./IntuneHydrationKit.psd1 -Force`
- Run single test files directly with `Invoke-Pester -Path ./Tests/Public/Connect-IntuneHydration.Tests.ps1 -Output Detailed`

## Additional Function Categories

### Win32 / WinGet App Packaging (Private Functions)
The module includes a full Win32 app packaging pipeline for creating `.intunewin` packages from bundled WinGet app templates:

- `New-IntuneWinPackage` - Packages a source directory into `.intunewin` format (zipping, encryption, Detection.xml generation)
- `New-IntuneWinPackagingContext` - Creates a packaging context with source, output, encryption key, paths
- `Expand-IntuneWinPackageEncryptedContent` - Extracts encrypted content from `.intunewin` for upload
- `Publish-IntuneWin32AppContent` - Orchestrates upload: create content version, chunked Azure Storage upload, commit with encryption metadata, mark `committedContentVersion`
- `New-IntuneWin32AppPayload` - Converts a hashtable configuration into a `win32LobApp` Graph payload with detection/requirement rules, OS mapping, return codes, and icon embedding
- `ConvertTo-IntuneWinDetectionRule` - Converts configuration rules to Graph detection rules (MSI, Registry, File, Script). Accepts `$Rule.ScriptFile` relative paths resolved against `$ScriptRootPath`
- `ConvertTo-IntuneWinRequirementRule` - Converts configuration rules to Graph requirement rules (Registry, File, Script, MSI). Script content is Base64-encoded

Key patterns:
- Both detection and requirement converters use an internal `ConvertTo-BoolValue` helper that normalizes strings like `"true"`, `"1"`, `"yes"`/`"false"`, `"0"`, `"no"` to boolean
- OS release codes (e.g. `W10_1607`, `W11_24H2`) are mapped to Graph values (`v10_1607`, `v10_21H1`) via a hardcoded `$releaseMap` in `New-IntuneWin32AppPayload`
- Default return codes are always included: 0 (success), 1707 (success), 3010 (softReboot), 1641 (hardReboot), 1618 (retry)

### CIS Baseline Import (`Import-CISBaseline`)
Imports bundled CIS benchmark policies from `Templates/CISBaselines/`. Routes each policy to the correct Graph endpoint based on its `@odata.type` (Settings Catalog, Compliance, Device Configuration). Supports `SkipIfExists` import mode and template-scoped deletion.

### WinGet App Import (`Import-IntuneWinGetApp`)
- Reads templates from `Templates/MobileApps/Windows/WinGet/` (or Presets subfolder)
- Uses bundled `resolvedPackage` metadata; live WinGet manifest resolution and custom WinGet app templates are not supported at import time
- Generates wrapper PSADT/WinGet scripts, packages with `New-IntuneWinPackage`, creates the Win32 app via Graph, publishes content with `Publish-IntuneWin32AppContent`
- Supports proactive remediation script generation (`-RemediationEnabled`)
- Uses `$script:TemplatesPath` fallback chain when resolving paths

### Graph Request Wrapper (`Invoke-HydrationGraphRequest`)
- Wraps `Invoke-MgGraphRequest` with single-request retry logic (429, 500+)
- `Resolve-GraphUri` strips the full `https://graph.microsoft.com` prefix if present
- `Get-GraphUriForLogging` truncates query parameter values for safe debug logging
- `Get-GraphBodySummary` describes payloads without leaking sensitive data (returns key counts and type names, not values)
- `Resolve-GraphErrorRecord` drills into `$_.Exception.InnerException.ErrorRecord` to find the correct status code for retry decisions

### Template Loading & Filtering
- `Get-HydrationTemplates` - Loads all JSON files from a Templates subdirectory recursively
- `Get-FilteredTemplates` - Applies platform filtering on top with four strategies (`Prefix`, `Suffix`, `Directory`, `Folder`)
- `Get-TemplateDisplayNames` - Extracts displayNames from templates into a `HashSet[string]` for dual-lookup existence checks

### Property & Object Helpers
- `Remove-ReadOnlyGraphProperties` - Recursively strips `id`, `createdDateTime`, `lastModifiedDateTime`, `version`, `@odata.context`, `#*` metadata, and any additional properties passed. Handles circular references via `HashSet` with `ReferenceEqualityComparer`
- `Copy-DeepObject` - Deep clone via `[Management.Automation.PSSerializer]::Serialize/Deserialize`
- `New-HydrationDescription` - Appends hydration marker to descriptions with configurable separator (default ` - `, use `' '` for resources that reject special characters like Autopilot profiles)
- `Get-HydrationMarkerSet` - Returns both primary and legacy markers for backward-compatible detection

### Pagination Helper (`Get-GraphPagedResults`)
Follows `@odata.nextLink` automatically. Has special workaround for `Invoke-MgGraphRequest` dictionary deserialization failures on duplicate keys (falls back to `-OutputType HttpResponseMessage` + `ConvertFrom-Json`, where PSCustomObject uses last-key-wins semantics).

## CI/CD

GitHub Actions workflow (`ci.yml`) runs on push/PR across Windows, macOS, and Ubuntu:
1. `./build.ps1` (bootstrap)
2. `./build.ps1 -Task Analyze`
3. `./build.ps1 -Task Test`
4. `./build.ps1 -Task Build`

Publish to PSGallery + GitHub release on version tag push (`v*.*.*`). Tag version must match manifest version.

### Group Import (`Invoke-GroupBatchImport`)
- Two-phase batch creation: first phase batches existence checks across groups ([IHD] + legacy unprefixed names), second phase batches POST creates for non-existent groups
- `ConvertTo-GroupBody` generates safe `mailNickname` values: alphanumeric-only, truncated to 64 chars, derived from displayName
- Deletion is template-scoped via optional `KnownNames` HashSet: only deletes groups with hydration marker AND unprefixed name match

### Logging (`Write-HydrationLog` / `Initialize-HydrationLogging`)
- `Initialize-HydrationLogging` sets `$script:LogPath` and `$script:CurrentLogFile`
- Log files and reports default to an OS temp path under `IntuneHydrationKit/`; `reporting.outputPath` or `-ReportOutputPath` can override report output
- Use `Write-HydrationLog` with levels `Info`, `Warning`, `Error`, `Success` for consistent output formatting

### Graph Scopes
Required scopes (returned by `Get-HydrationGraphScopes`):
```
DeviceManagementConfiguration.ReadWrite.All
DeviceManagementServiceConfig.ReadWrite.All
DeviceManagementManagedDevices.ReadWrite.All
DeviceManagementScripts.ReadWrite.All
DeviceManagementApps.ReadWrite.All
Group.ReadWrite.All
Policy.Read.All
Policy.ReadWrite.ConditionalAccess
Application.Read.All
Directory.ReadWrite.All
LicenseAssignment.Read.All
Organization.Read.All
```

## Important Notes

- Custom Windows compliance templates contain placeholders (`REPLACE_SCRIPT_ID`, `REPLACE_RULES_BASE64`) that must be replaced before use
- OpenIntuneBaseline templates are bundled under `Templates/OpenIntuneBaseline/` (can also download dynamically via `Get-OpenIntuneBaseline`)
- Uses beta Graph API endpoints for certain Intune resources
- When running delete then create, always run DELETE first to clean up legacy resources
- `scripts/` directory contains build helpers and dev utilities (not published to PSGallery)
