# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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