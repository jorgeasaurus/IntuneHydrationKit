# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **All import functions now use tag-aware skip logic** — Previously, every import function would skip any object matching by `displayName` alone, regardless of whether it was created by the kit. Now each function only skips objects that have the `"Imported by Intune Hydration Kit"` marker in their `description` or `notes` field, allowing the kit to create its own tagged version alongside pre-existing untagged objects. Affected functions:
  - `Import-IntuneMobileApp` (checks `notes` field)
  - `Import-IntuneCompliancePolicy` (checks `description` field)
  - `Import-IntuneAppProtectionPolicy` (checks `description` field)
  - `Import-IntuneDeviceFilter` (checks `description` field)
  - `Import-IntuneEnrollmentProfile` — all 4 sub-types: Autopilot, ESP, macOS DEP, Device Preparation (checks `description` field)

- **Delete operations now scoped to template names** — Previously, `-RemoveExisting` would delete any object with the hydration kit tag, including objects created by other tools (e.g., CIS policies from the web toolkit). Now delete operations require both the kit tag AND a matching template name. This prevents accidental deletion of objects created by other tools that share the same tag. Affected functions:
  - `Import-IntuneBaseline` (scoped to OpenIntuneBaseline template names)
  - `Import-IntuneMobileApp` (scoped to MobileApps template names)
  - `Import-IntuneAppProtectionPolicy` (scoped to AppProtection template names)
  - `Import-IntuneDeviceFilter` (scoped to Filters template names)
  - `Import-IntuneEnrollmentProfile` (scoped to Enrollment template names)
  - `Import-IntuneConditionalAccessPolicy` and `Import-IntuneNotificationTemplate` already used template name matching

### Added

- **`Get-TemplateDisplayNames` private helper** — Extracts display names from template JSON files into a case-insensitive lookup set. Supports nested array properties (e.g., device filter templates), file-based naming, and optional prefix. Used by all delete flows for template-scoped safety.

### Changed

- **`Test-HydrationKitObject` now accepts both `-Description` and `-Notes` parameters** — Returns `$true` if either field contains the hydration kit marker. Backward compatible with existing callers that only pass `-Description`.

## [0.4.0] - 2026-01-18

### Added

- **Batch Graph API operations** for dramatically improved performance:
  - Group imports now batched (existence checks + creation in batches of 10)
  - Policy imports batched for baselines, compliance, app protection, conditional access, and mobile apps
  - Device filter imports batched
  - ~89% reduction in API calls for group operations
  - ~90% reduction in API calls for policy imports
- **Bundled OpenIntuneBaseline templates** - Templates now included in module, no external downloads required
- `Invoke-GraphBatchOperation` private helper for standardized batch processing with retry logic

### Changed

- `Import-IntuneBaseline` now uses bundled `Templates/OpenIntuneBaseline` by default
- Full hydration runtime reduced from ~180 seconds to ~70 seconds (61% faster)
- Module-level `$script:MaxBatchSize` variable for consistent batch sizing across functions


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
