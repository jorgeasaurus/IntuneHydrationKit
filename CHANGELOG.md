# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2026-04-22

### Fixed

- **Minor bug fixes and enhancements**: Included smaller reliability fixes and import-path improvements across CIS and related baseline workflows.

### Changed

- **CIS baseline coverage**: Added a substantial amount of new bundled CIS baseline templates across supported policy categories.
- **General maintainability**: Included additional workflow and code-quality enhancements throughout the hydration process.

## [0.6.1] - 2026-04-16

### Changed

- **Bundled Baselines by Default**: OpenIntuneBaseline policies now always import from the bundled `Templates/OpenIntuneBaseline/` directory instead of downloading from GitHub. Removed `BaselineRepoUrl`, `BaselineBranch`, and `BaselineDownloadPath` parameters from `Invoke-IntuneHydration` and the wrapper script. The `openIntuneBaseline` configuration section has been removed from the settings schema and example files. `Get-OpenIntuneBaseline` remains available as a standalone utility for manual downloads, and `Import-IntuneBaseline -BaselinePath` still accepts a custom path override.

## [0.6.0] - 2026-04-04

### Added

- **Retry-After Header Support**: `Invoke-GraphBatchOperation` now captures `Retry-After` headers from individual 429/503 batch responses and honors the longest delay before retrying, falling back to exponential backoff when the header is absent
- **Paginated Query Retry Logic**: `Get-GraphPagedResults` now retries on 429/5xx transient errors with Retry-After support and exponential backoff (max 3 retries per page)
- **`[OutputType()]` Annotations**: Added to 8 private helpers: `Get-FilteredTemplates`, `Get-GraphErrorMessage`, `Get-HydrationTemplates`, `Get-ResultSummary`, `New-HydrationDescription`, `New-HydrationResult`, `Remove-ReadOnlyGraphProperties`, `Test-HydrationKitObject`
- **Comment-Based Help**: Completed `.DESCRIPTION` and `.EXAMPLE` sections for `Write-HydrationLog`, `Initialize-HydrationLogging`, and `Import-HydrationSettings`
- **Test Coverage**: Expanded from 458 to 648 tests (+190) with 13 new test files:
  - 9 private function tests: `Get-GraphErrorMessage`, `Get-HydrationTemplates`, `Get-ObfuscatedTenantId`, `Get-PremiumP2ServicePlans`, `Get-ResultSummary`, `New-HydrationResult`, `Remove-ReadOnlyGraphProperties`, `Test-ConditionalAccessPolicyRequiresP2`, `Test-ConditionalAccessPolicyRequiresPreview`
  - 4 public function tests: `Import-IntuneBaseline`, `Import-IntuneAppProtectionPolicy`, `Import-IntuneConditionalAccessPolicy`, `Import-IntuneNotificationTemplate`
  - 429 throttle with Retry-After header test for `Invoke-GraphBatchOperation`

### Changed

- **Error Handling**: Replaced bare `throw` and `Write-Error` with `$PSCmdlet.ThrowTerminatingError()` and `$PSCmdlet.WriteError()` in 9 public functions (`Connect-IntuneHydration`, `Get-OpenIntuneBaseline`, `Import-HydrationSettings`, `Import-IntuneBaseline`, `Import-IntuneConditionalAccessPolicy`, `Import-IntuneEnrollmentProfile`, `Invoke-IntuneHydration`, `New-IntuneDynamicGroup`, `Test-IntunePrerequisites`) — all errors now include structured ErrorRecord objects with error IDs, categories, and target objects
- **Graph API Performance**: Added `$select` query parameter to 8+ GET requests across `Import-IntuneCompliancePolicy`, `Import-IntuneConditionalAccessPolicy`, `Import-IntuneEnrollmentProfile`, `Test-IntunePrerequisites`, and `Test-WindowsDriverUpdateLicense` to reduce response payload size
- **Centralized Hydration Marker**: Marker strings (`"Imported by Intune Hydration Kit"` and hyphenated variant) consolidated into `$script:HydrationMarker` and `$script:HydrationMarkerAlt` module-scoped variables in `IntuneHydrationKit.psm1`, used by `Test-HydrationKitObject` and `New-HydrationDescription`

## [0.5.0] - 2026-03-29

### Added

- **`[IHD]` Name Prefix**: All imported objects are now prefixed with `[IHD]` for easy identification and filtering in the Intune portal
- **Batch Graph API Operations**: Groups, policies, filters, and apps now use batched API calls (up to 10 per batch) for significantly faster execution (~61% improvement)
- **Bundled OpenIntuneBaseline Templates**: OIB templates are now included in the module — no external download required at runtime
- **Notification Template Support**: Import and delete notification message templates (`Templates/Notifications/`)

### Changed

- **Performance**: Full hydration runs reduced from ~180s to ~70s via batch operations
- Delete mode now identifies objects by both `[IHD]` name prefix and description marker for more reliable matching
- `Get-TemplateDisplayNames` returns `HashSet[string]` (case-insensitive) instead of plain collection — help text updated to match
- `Import-IntuneMobileApp` now uses `-Notes` parameter (instead of `-Description`) for mobile app notes field
- Security Baselines count corrected from 91 to 94

### Fixed

- **Delete mode**: Graph API duplicate key error when listing groups (`displayName` dictionary collision)
- **Delete mode**: Null-valued expression errors when `$response.value` is null or empty
- **Delete mode**: Scriptblock scope bug where `$results += $item` created a new local variable instead of accumulating
- **Delete mode**: `Get-TemplateDisplayNames` returned empty `HashSet` that PowerShell enumerated to `$null`; fixed with comma operator
- **Delete mode**: Baseline path resolution was inside create-only conditional block; moved outside
- **Delete mode**: Notification template prefix-stripping for name matching
- **Batch operations**: Empty batch responses now correctly marked as Failed instead of assumed success
- **Batch operations**: Added bounds check and TryParse for batch response ID mapping to prevent null dereference
- **Batch operations**: `Get-GraphPagedResults` uses `List[object]` instead of O(n²) array reallocation for paging
- **Group delete safety**: Template-scoped deletes via `-KnownNames` parameter — only groups matching current templates are deleted
- **Group batch import**: Null-safe prefix resolution defaults to `[IHD] ` when `$script:ImportPrefix` is null (dot-source safety)
- **Enrollment profiles**: Dashes stripped only from original description text, not from hydration tag; uses space separator via `New-HydrationDescription -Separator ' '`
- **JSON template parsing**: Malformed group template files no longer crash the entire hydration run (per-file try/catch)
- **Group prefix mismatch**: Existence check now queries both prefixed and unprefixed names, preventing duplicate creation on re-runs
- **Cross-platform paths**: `Import-IntuneBaseline` uses chained `Join-Path` calls instead of Windows-style backslash separators
- **Hardcoded prefix regex**: All 9 delete-matching regex patterns now use `[regex]::Escape()` for dynamic prefix support
- **Description helper consistency**: `Import-IntuneCompliancePolicy` and `Invoke-GroupBatchImport` now use `New-HydrationDescription` instead of manual concatenation
- **Whitespace handling**: `New-HydrationDescription` uses `[string]::IsNullOrWhiteSpace()` instead of truthy check
- **Cross-platform tests**: `Get-FilteredTemplates` path splitting now uses `[/\\]` regex instead of OS-native separator
- **CI pipeline**: Pinned GitHub Actions to specific versions, added `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` env var
- **LICENSE file**: Restored to git tracking (was accidentally deleted from feature branch)

## [0.3.4] - 2026-01-17

### Added

- **Windows Autopilot device preparation** support:
  - New enrollment profile template: Windows Autopilot device preparation - User Driven
  - New static group: Windows Autopilot device preparation (with Intune Provisioning Client as owner)
  - Automatic group assignment for device preparation policy
- Platform filtering for template imports - filter baselines, compliance policies, and other imports by platform (Windows, macOS, iOS, Android, Linux)
- `settings.schema.json` for JSON schema validation of settings files

## [0.3.3] - 2026-01-11

### Added

- **Issue #15**: License-based dynamic user groups with simplified membership rules:
  - `Entra - License - E3` (Exchange Online Plan 2)
  - `Entra - License - E5` (Entra ID P2)
  - `Entra - License - F3` (Exchange Kiosk)
  - `Entra - License - Business Premium` (Defender for Business)
  - `Entra - License - Copilot` (M365 Copilot Business Chat)
  - `Entra - License - Power BI Pro`
  - `Entra - License - Visio`
  - `Entra - License - Project`
- Dynamic groups count increased from 43 to 51

### Changed

- OpenIntuneBaseline now pulls from [maintained fork](https://github.com/jorgeasaurus/OpenIntuneBaseline) to prevent unplanned breaking changes from upstream
- **Issue #15**: Simplified dynamic group membership rules - removed complex exclusion logic (`-and -not`) for faster group processing
- Updated README with fork notice and acknowledgment of original OpenIntuneBaseline project

## [0.3.1] - 2026-01-09

### Fixed

- **Issue #14**: M365 Business Premium license not detected for Windows Driver Updates
  - Added `WINDOWSUPDATEFORBUSINESS_DEPLOYMENTSERVICE` service plan to license detection
  - This service plan is included in M365 Business Premium and enables driver update functionality

## [0.3.0] - 2026-01-04

### Fixed

- **Issue #12**: Logs and reports now created when using `-WhatIf` parameter
  - Log files are always written regardless of WhatIf mode
  - Summary reports (both Markdown and JSON) are always generated
  - Report mode correctly displays "Dry-Run" when WhatIf is enabled
- **Issue #13**: TenantId parameter consistency across functions
  - Both `Connect-IntuneHydration` and `Invoke-IntuneHydration` now require GUID format
  - Documentation and examples updated to reflect GUID-only requirement
- Tenant ID obfuscation in console output for security (e.g., `0e3028c5****-****-****-eea5ff7417b5`)

### Changed

- Logging and reporting operations now explicitly bypass `-WhatIf` using `-WhatIf:$false`
- `TenantId` parameter validation standardized to GUID format across all public functions
- Added WhatIf mode tests to verify logging and reporting behavior

## [0.2.9] - 2026-01-04

### Added

- 7 new Conditional Access policy templates (total now 21 policies)
  - Block access to Office365 apps for users with insider risk
  - Block all agent identities from accessing resources
  - Block all agent users from accessing resources
  - Block high risk agent identities from accessing resources
  - Require multifactor authentication for risky sign-ins
  - Require password change for high-risk users
  - Secure account recovery with identity verification (Preview)
- Premium P2 license validation for Conditional Access policies requiring Entra ID P2
- Preview feature detection for Conditional Access policies requiring preview features
- `Get-PremiumP2ServicePlans` helper function for centralized P2 SKU list management

### Changed

- README.md updated with correct Conditional Access count (21 policies) and link to Microsoft Learn documentation
- Enhanced `Test-IntunePrerequisites` with comprehensive E5/A5/EMS suite detection
- Fixed empty rows in hydration summary reports
- Fixed missing Type column values in Conditional Access import results

## [0.2.8] - 2026-01-02

### Added

- Automatic replacement of `%OrganizationId%` placeholder with tenant ID during OpenIntuneBaseline import
- Verbose logging when placeholder replacement occurs in policy templates

### Changed

- `Import-IntuneBaseline` now processes JSON templates and replaces `%OrganizationId%` with actual tenant ID before importing to Graph API
- Affects OneDrive configuration policies that require tenant-specific settings (Known Folder Move, etc.)

## [0.2.7] - 2026-01-01

### Fixed

- Hydration summary report now inserts a clean newline after the table header so the **All Operations** section renders correctly in Markdown viewers.

## [0.2.6] - 2025-12-21

### Added

- Notion mobile app template
- VLC mobile app template
- VM-based dynamic groups (12 new groups for AVD, Windows 365, Hyper-V, VMware, VirtualBox, Parallels, QEMU/KVM)
- VM-based device filters (12 new filters matching the dynamic groups)
- Template-based device filter import (`Templates/Filters/` directory)
- Device filter templates organized by platform (Windows, macOS, iOS, Android)
- CHANGELOG.md

### Changed

- Refactored `Import-IntuneDeviceFilter` to use JSON templates instead of hardcoded definitions
- Dynamic Groups count increased from 31 to 43
- Device Filters count increased from 12 to 24
- Moved changelog from README.md to dedicated CHANGELOG.md

## [0.2.5] - 2025-12-18

### Added

- Dynamic enrollment profile discovery (auto-detects templates by @odata.type)
- Cross-platform logging to OS temp directories (Windows/macOS/Linux)
- Reports now written to OS temp directory by default

## [0.2.4] - 2025-12-15

### Added

- WhatsApp mobile app template
- Spotify mobile app template
- Microsoft Copilot mobile app template
- Power BI Desktop mobile app template
- Windows App mobile app template
- Windows Terminal mobile app template
- Windows Self-Deploy Autopilot Profile

## [0.2.3] - 2025-12-10

### Added

- Slack mobile app template
- Microsoft Teams mobile app template
- Windows, macOS, and Linux build test support

### Changed

- Updated module dependencies

## [0.2.2] - 2025-12-05

### Fixed

- Adobe Acrobat Reader DC JSON template updated to import properly

## [0.2.1] - 2025-12-01

### Added

- Static Groups support with `New-IntuneStaticGroup` function
- `-StaticGroups` parameter to `Invoke-IntuneHydration`
- `staticGroups` option to settings file imports section
- Static group templates in `Templates/StaticGroups/` directory
- Update Ring groups (Pilot, UAT) for Windows Update for Business
- Ownership groups (Corporate, BYOD)
- User-based groups (Intune Licensed Users, Update Ring Broad)
- Platform-specific ownership groups (macOS, iPhone, iPad, Android)
- Android Enterprise groups (Work Profile, Fully Managed)
- Windows ConfigMgr Managed devices group
- Mobile Apps support with `Import-IntuneMobileApp` function
- `-MobileApps` parameter to `Invoke-IntuneHydration`
- `mobileApps` option to settings file imports section
- `Scripts/New-MobileAppTemplate.ps1` helper to generate mobile app JSON templates
- Support for winGetApp (Microsoft Store), macOSMicrosoftEdgeApp, macOSOfficeSuiteApp, officeSuiteApp types
- Mobile app templates in `Templates/MobileApps/` directory
- PowerShell Gallery publishing support (`Install-Module IntuneHydrationKit`)
- `Invoke-IntuneHydration` as exported module function
- Backward compatible wrapper script for cloned repository users
- InvokeBuild-based build system for CI/CD
- GitHub Actions workflows for automated testing and publishing
- Pester tests for main orchestrator function

### Changed

- Expanded Dynamic Groups from 12 to 30+

### Fixed

- PSScriptAnalyzer warnings (variable naming conflicts)
- Notification template deletion (now matches by template name)

## [0.1.8] - 2025-11-20

### Added

- Full parameter-based invocation support
- Two mutually exclusive modes: settings file (`-SettingsPath`) or parameters (`-TenantId` + auth)
- `-All` switch to enable all targets at once
- PowerShell `-WhatIf` preview mode support across invocation modes
- Parameters for all configuration options (tenant, auth, targets, reporting)
- Windows Driver Update license pre-check to avoid 403 errors
- `LicenseAssignment.Read.All` scope for license validation checks
- `Organization.Read.All` scope for tenant organization details

## [0.1.4] - 2025-11-15

### Added

- `DeviceManagementScripts.ReadWrite.All` scope for custom compliance scripts
- `Application.Read.All` scope for Conditional Access policies targeting specific applications
- `Policy.Read.All` scope for querying existing Conditional Access policies

### Changed

- Updated prerequisite checks to validate Graph permission scopes

### Removed

- MDM authority check from prerequisites

## [0.1.3] - 2025-11-10

### Fixed

- Image paths in README.md

## [0.1.2] - 2025-11-08

### Changed

- Refactored code structure for improved readability and maintainability

## [0.1.1] - 2025-11-05

### Fixed

- Module manifest with correct author and company details

## [0.1.0] - 2025-11-01

### Added

- OpenIntuneBaseline integration (auto-downloads latest policies)
- Compliance policy templates (Windows, macOS, iOS, Android, Linux)
- App protection policies (Android/iOS MAM)
- Dynamic groups and device filters
- Enrollment profiles (Autopilot, ESP)
- Conditional Access starter pack (always created disabled)
- Safe deletion (only removes kit-created objects)
- Multi-cloud support (Global, USGov, USGovDoD, Germany, China)
- WhatIf/dry-run mode
- Detailed logging and reporting
