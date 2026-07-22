<p align="center">
  <img src="media/SocialCard.png" alt="Intune Hydration Kit social card">
</p>

<p align="center">
  <strong>Automate your Microsoft Intune tenant configuration with best-practice defaults</strong>
</p>

<p align="center">
  <a href="https://github.com/jorgeasaurus/IntuneHydrationKit/actions/workflows/ci.yml"><img src="https://github.com/jorgeasaurus/IntuneHydrationKit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://www.powershellgallery.com/packages/IntuneHydrationKit"><img src="https://img.shields.io/powershellgallery/v/IntuneHydrationKit?label=PSGallery&color=blue" alt="PowerShell Gallery Version"></a>
  <a href="https://www.powershellgallery.com/packages/IntuneHydrationKit"><img src="https://img.shields.io/powershellgallery/dt/IntuneHydrationKit?label=Downloads&color=green" alt="PowerShell Gallery Downloads"></a>
  <a href="https://github.com/jorgeasaurus/IntuneHydrationKit/blob/main/LICENSE"><img src="https://img.shields.io/github/license/jorgeasaurus/IntuneHydrationKit" alt="License"></a>
  <img src="https://img.shields.io/badge/PowerShell-7.0%2B-blue?logo=powershell&logoColor=white" alt="PowerShell 7.0+">
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey" alt="Platform">
</p>

<p align="center">
  <a href="https://github.com/jorgeasaurus/IntuneHydrationKit/stargazers"><img src="https://img.shields.io/github/stars/jorgeasaurus/IntuneHydrationKit?style=social" alt="GitHub Stars"></a>
  <a href="https://github.com/jorgeasaurus/IntuneHydrationKit/commits/main"><img src="https://img.shields.io/github/last-commit/jorgeasaurus/IntuneHydrationKit" alt="Last Commit"></a>
  <a href="https://github.com/jorgeasaurus/IntuneHydrationKit/releases/latest"><img src="https://img.shields.io/github/v/release/jorgeasaurus/IntuneHydrationKit?label=Latest%20Release" alt="Latest Release"></a>
</p>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#interactive-tui">Interactive TUI</a> •
  <a href="#automation-and-settings-files">Automation</a> •
  <a href="#safety-features">Safety Features</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## Overview

The Intune Hydration Kit is a PowerShell module that bootstraps Microsoft Intune tenants with practical baseline configurations. It includes vetted [OpenIntuneBaseline](https://github.com/jorgeasaurus/OpenIntuneBaseline) policies, bundled CIS benchmark-derived policies from [IntuneBaselines](https://github.com/jorgeasaurus/IntuneBaselines), compliance policies, dynamic groups, and more, turning hours of manual setup into a single command.

> **Note:** This kit uses a [maintained fork](https://github.com/jorgeasaurus/OpenIntuneBaseline) of the original [OpenIntuneBaseline](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline) repository. OpenIntuneBaseline and CIS baseline content from [IntuneBaselines](https://github.com/jorgeasaurus/IntuneBaselines) are bundled with the module and periodically refreshed only after validation and testing, which prevents unplanned upstream changes from affecting your deployments.

### Demo

<p align="center">
  <img src="media/demo.gif" alt="Demo" width="900">
</p>

### What Gets Created

These counts reflect the bundled template set at the time of the latest validated release and may change as templates are added or revised.

| Category | Count | Description |
| ---------- | ------- | ------------- |
| Dynamic Groups | 59 | Device and user targeting groups (OS, manufacturer, Autopilot, ownership, VMs, license-based) |
| Static Groups | 5 | Update ring groups (Pilot, UAT) and Autopilot device preparation group |
| Device Filters | 38 | Platform, OS-version, architecture, manufacturer, and VM-based filters (Windows, macOS, iOS, Android) |
| OpenIntuneBaseline | 99 | [OpenIntuneBaseline](https://github.com/jorgeasaurus/OpenIntuneBaseline) policies (Windows, macOS, iOS, Android) - bundled, no download required |
| CIS Baselines | 728 | Bundled [IntuneBaselines](https://github.com/jorgeasaurus/IntuneBaselines) CIS benchmark-derived policies across Windows, macOS, iOS, Android, Edge, Chrome, and related administrative template workloads |
| Compliance Policies | 10 | Multi-platform compliance (Windows, macOS, iOS, Android, Linux) |
| App Protection | 8 | MAM policies following [Microsoft's App Protection Framework](https://learn.microsoft.com/en-us/intune/intune-service/apps/app-protection-framework) (Level 1-3 for iOS and Android) |
| Mobile Apps | 8 | Bundled legacy mobile app templates (macOS Edge, macOS M365 Apps, Windows M365 Apps, plus Windows Store templates for Adobe Acrobat Reader DC, Company Portal, PowerShell, Spotify, and WhatsApp) |
| WinGet Win32 Apps | 28 | [Bundled Windows WinGet app catalog](#windows-winget-app-catalog) packaged as Intune Win32 apps |
| Notification Templates | 1 | Notification message templates for compliance and enrollment |
| Enrollment Profiles | 4 | Autopilot deployment profiles, Enrollment Status Page, and Autopilot device preparation |
| Conditional Access | 21 | [Starter pack policy templates](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policy-common) (created disabled) |

---

## Important Warnings

> **⚠️ READ BEFORE USE**

### This Tool Can Modify Your Production Environment

- **Creates objects** in your Intune tenant (policies, groups, filters)
- **Can delete objects** when run with delete mode enabled
- **Modifies Conditional Access** policies (though always created disabled)

### Recommendations

1. **Test in a non-production tenant first** - Use a dev/test tenant before running against production
2. **Always preview changes first** - Use dry-run create in the TUI, or `-WhatIf` in automation mode
3. **Review enabled targets** - Start with a small TUI workload selection before selecting everything
4. **Have a rollback plan** - Know how to remove configurations if needed

### Deletion Safety

When using delete mode (`-Delete` parameter or `"delete": true` in settings), the kit will **only delete objects that it created**:

- Objects are identified by the `"Imported by Intune Hydration Kit"` marker; some resource types also use the `[IHD]` name prefix
- Conditional Access policies must also be in `disabled` state to be deleted
- Manually created objects with the same names will NOT be deleted

---

## Features

- **`[IHD]` Name Markers** - Most imported objects are prefixed with `[IHD]`; mobile apps and WinGet apps append ` - [IHD]` and also rely on hydration markers for ownership
- **Batch API Operations** - Groups, policies, filters, and apps use batched Graph API calls (up to 10 per batch) for ~61% faster execution
- **Retry-After Throttle Handling** - Automatic retry with `Retry-After` header support on 429/503 Graph API responses
- **Bundled Baselines** - OpenIntuneBaseline and CIS baseline templates are included in the module (no external download required)
- **Idempotent** - Safe to run multiple times; skips existing configurations
- **Dry-Run Mode** - Preview selected TUI workloads before applying; automation can use PowerShell `-WhatIf`
- **Safe Deletion** - Only removes objects created by this kit (identified by the hydration marker, with prefixes used where applicable)
- **Multi-Platform** - Supports Windows, macOS, iOS, Android, and Linux
- **Platform Filtering** - Import resources for specific platforms only (e.g., `-Platform Windows,macOS`)
- **Architecture Filters** - Windows and macOS assignment filters use Intune's native `device.cpuArchitecture` property for policy and app targeting
- **Detailed Logging** - Full audit trail of all operations
- **Elapsed Time Tracking** - Final summary output and reports include total hydration time
- **Summary Reports** - Markdown and JSON reports of all changes
- **WinGet Win32 Apps** - Windows app hydration backed by bundled WinGet templates and packaged into Intune Win32 apps without requiring `IntuneWinAppUtil.exe`

---

## Prerequisites

### Required PowerShell Version

- PowerShell 7.0 or later

### Required Modules

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

> **Note:** This module uses `Invoke-MgGraphRequest` for all Graph API calls, so only the Authentication module is required.

### Required Permissions

For interactive runs, use a Global Administrator account. Intune Graph APIs can reject PIM-elevated or non-Global Administrator accounts even when Graph consent is present.

Why: Microsoft documents that Intune Graph access requires both Graph permission scopes and user role permissions. Microsoft also documents that after PIM activates a role, downstream application access can lag or remain cached depending on the application architecture. In practice, Intune's Graph backend can return 401/403 for PIM-elevated Global Administrator sessions while a permanently assigned Global Administrator works.

The authenticated user/app also needs these Microsoft Graph permissions:

- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
- `DeviceManagementManagedDevices.ReadWrite.All`
- `DeviceManagementScripts.ReadWrite.All`
- `DeviceManagementApps.ReadWrite.All`
- `Group.ReadWrite.All`
- `Policy.Read.All`
- `Policy.ReadWrite.ConditionalAccess`
- `Application.Read.All`
- `Directory.ReadWrite.All`
- `LicenseAssignment.Read.All`
- `Organization.Read.All`

---

## Installation

### Option A: PowerShell Gallery (Recommended)

Install directly from the PowerShell Gallery:

```powershell
Install-Module -Name IntuneHydrationKit -Scope CurrentUser
```

To update to the latest version:

```powershell
Update-Module -Name IntuneHydrationKit
```

### Option B: Clone from GitHub

For development or to use the latest unreleased changes:

```powershell
git clone https://github.com/jorgeasaurus/IntuneHydrationKit.git
cd IntuneHydrationKit
Import-Module ./IntuneHydrationKit.psd1
```

---

## Quick Start

The TUI is the main way to run Intune Hydration Kit. It guides you through Azure cloud, operation mode, workload targets, platform filtering, and final confirmation before any Graph write calls run. The tenant ID is discovered after browser sign-in.

Install the module, then start the guided flow:

```powershell
Install-Module -Name IntuneHydrationKit -Scope CurrentUser
Invoke-IntuneHydration
```

For the first pass, choose **Dry-run create** in the TUI and select a small workload such as Device Filters. After reviewing the summary, rerun the TUI and choose **Create** for the workloads you want to apply.

Use command-line parameters or settings files only when you need repeatable automation, service-principal authentication, custom report paths, custom report formats, or PowerShell `-WhatIf`.

---

## Interactive TUI

Run with no arguments to launch the guided console experience:

```powershell
Invoke-IntuneHydration
```

<p align="center">
  <img src="media/TUI.png" alt="Intune Hydration Kit interactive TUI" width="900">
</p>

The wizard prompts for:

- Azure cloud environment
- Operation mode: create, delete, or dry-run create
- Workload targets
- Platform filter
- Verbose logging
- Final confirmation

TUI behavior:

- Authentication is interactive browser sign-in.
- Dry-run create previews the selected workload without writing to Graph.
- No workloads are selected by default.
- At least one workload must be selected before review.
- Platform defaults to `All`; choosing a specific platform clears `All`.
- Configuration is not saved to a settings file.
- Type `q` at any prompt to cancel before Graph calls run.

The TUI hands off to the same execution engine as parameter and settings-file mode, so reports, logs, safety checks, and deletion protections are identical.

---

## Automation and Settings Files

Use automation mode when the run must be repeatable or non-interactive. The full command patterns live in [docs/Invocation-Examples.md](docs/Invocation-Examples.md).

```powershell
Invoke-IntuneHydration -TenantId "your-tenant-id" -Interactive -Create -All -WhatIf
```

Use settings files only when you want reusable configuration:

```powershell
Invoke-IntuneHydration -SettingsPath ./settings.json -WhatIf
```

---

## Command-Line Parameters

Use PowerShell help for the complete, always-current parameter list:

```powershell
Get-Help Invoke-IntuneHydration -Detailed
```

### Parameter Reference

| Parameter | Purpose |
| ----------- | ------- |
| `-TenantId` | Target tenant ID |
| `-TenantName` | Optional tenant name for display |
| `-Interactive` | Use interactive browser-based authentication |
| `-ClientId` | Service principal application ID |
| `-ClientSecret` | Service principal client secret |
| `-Environment` | Cloud environment (`Global`, `USGov`, `USGovDoD`, `Germany`, `China`) |
| `-Create` | Create configurations |
| `-Delete` | Delete kit-created configurations |
| `-Force` | Skip delete confirmation prompts |
| `-OpenIntuneBaseline` | Process OpenIntuneBaseline policies |
| `-CISBaselines` | Process bundled CIS baseline policies |
| `-ComplianceTemplates` | Process compliance templates |
| `-AppProtection` | Process app protection policies |
| `-NotificationTemplates` | Process notification templates |
| `-EnrollmentProfiles` | Process enrollment profiles |
| `-DynamicGroups` | Process dynamic groups |
| `-StaticGroups` | Process static groups |
| `-DeviceFilters` | Process device filters |
| `-ConditionalAccess` | Process Conditional Access starter pack |
| `-MobileApps` | Process mobile apps |
| `-All` | Enable all targets |
| `-Platform` | Filter supported resource types by platform |
| `-ReportOutputPath` | Write reports to a custom folder |
| `-ReportFormats` | Select report formats (`markdown`, `json`) |
| `-SettingsPath` | Use settings-file mode |
| `-WhatIf` | Preview changes without applying them |
| `-Verbose` | Emit verbose diagnostics |

---

## Settings File Reference

The full settings-file structure and examples live in [docs/Invocation-Examples.md](docs/Invocation-Examples.md).

#### Selective Targets

Enable only the categories you need. See [docs/Invocation-Examples.md](docs/Invocation-Examples.md) for the JSON example.

##### Windows WinGet App Catalog

Windows mobile app hydration imports the full bundled Windows catalog by default. See [docs/Invocation-Examples.md](docs/Invocation-Examples.md) for the JSON example.

- `templateIds` narrows WinGet-backed imports to specific bundled templates.
- `remediation.enabled` defaults to `true` and creates/updates WinGet app update remediation scripts when supported.
- Generated remediations are unassigned by design; assign after review.
- Generated scripts are saved to a temp folder and listed in the summary report.
- To add another app, open a request issue or submit a PR that adds a bundled template.

### WinGet App Hydration Prerequisites

WinGet-backed Windows app hydration has a few additional prerequisites beyond Graph access:

- **App Installer / `winget.exe` on managed devices** - The generated install and uninstall wrappers call `winget.exe`. Devices need Microsoft App Installer installed so `winget.exe` can be resolved at runtime.
- **Outbound access to app sources** - WinGet installs pull vendor installers defined in the WinGet manifest. Make sure devices can reach the package download locations required by your selected templates.
- **No external packaging utility required** - The kit builds `.intunewin` content with the repo-owned cross-platform packager, so the operator machine does not need `IntuneWinAppUtil.exe`.

| Display name | Publisher | Package identifier |
|---|---|---|
| 7-Zip | Igor Pavlov | `7zip.7zip` |
| Cursor | Anysphere | `Anysphere.Cursor` |
| Claude | Anthropic, PBC | `Anthropic.Claude` |
| Claude Code | Anthropic PBC | `Anthropic.ClaudeCode` |
| Docker Desktop | Docker Inc. | `Docker.DockerDesktop` |
| Everything | voidtools | `voidtools.Everything` |
| Foxit PDF Reader | Foxit Software Inc. | `Foxit.FoxitReader` |
| Git for Windows | The Git Development Community | `Git.Git` |
| GitHub Desktop | GitHub, Inc. | `GitHub.GitHubDesktop` |
| Google Chrome | Google LLC | `Google.Chrome` |
| Greenshot | Greenshot | `Greenshot.Greenshot` |
| Microsoft Edge | Microsoft Corporation | `Microsoft.Edge` |
| PowerToys | Microsoft Corporation | `Microsoft.PowerToys` |
| Microsoft Teams | Microsoft Corporation | `Microsoft.Teams` |
| Mozilla Firefox | Mozilla | `Mozilla.Firefox` |
| Notepad++ | Don Ho | `Notepad++.Notepad++` |
| Notion | Notion Labs Inc. | `Notion.Notion` |
| Power BI Desktop | Microsoft Corporation | `Microsoft.PowerBI` |
| PuTTY | Simon Tatham | `PuTTY.PuTTY` |
| ShareX | ShareX Team | `ShareX.ShareX` |
| Slack | Slack Technologies Inc. | `SlackTechnologies.Slack` |
| TreeSize Free | JAM Software | `JAMSoftware.TreeSize.Free` |
| Visual Studio Code | Microsoft Corporation | `Microsoft.VisualStudioCode` |
| VLC media player | VideoLAN | `VideoLAN.VLC` |
| Windows App | Microsoft Corp. | `Microsoft.WindowsApp` |
| Windows Terminal | Microsoft Corporation | `Microsoft.WindowsTerminal` |
| WinSCP | Martin Prikryl | `WinSCP.WinSCP` |
| Zoom Workplace | Zoom Communications, Inc. | `Zoom.Zoom` |

#### Platform Filtering

Filter imports by platform to only import resources for specific operating systems:

See [docs/Invocation-Examples.md](docs/Invocation-Examples.md) for the JSON examples and the list of affected resources.

## Safety Features

### Hydration Marker

Most objects created by this kit are identified by two markers:

1. **Name prefix:** `[IHD]` prepended to the display name (e.g., `[IHD] Windows - Default Compliance`)
2. **Description marker:**

```plaintext
Imported by Intune Hydration Kit
```

Mobile apps and WinGet apps are the notable exceptions to prefixing: they append ` - [IHD]` to their template display names and rely on the hydration marker (plus WinGet ownership metadata for WinGet apps) for safe cleanup.

These markers are used to:

- Identify objects created by this tool at a glance
- Prevent deletion of manually-created objects
- Enable safe cleanup operations

### Conditional Access Protection

Conditional Access policies receive additional protection:

- **Always created in `disabled` state** - Never automatically enabled
- **Deletion requires disabled state** - Cannot delete enabled CA policies
- **Manual review required** - You must manually enable policies after review

### WhatIf Support (Preview Mode)

For normal interactive use, choose **Dry-run create** in the TUI. For automation, use PowerShell `-WhatIf` in parameter or settings-file mode:

```powershell
# Parameter mode
./Invoke-IntuneHydration.ps1 -TenantId "guid" -Interactive -Create -All -WhatIf

# Settings file mode
./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -WhatIf
```

---

## Output and Reports

### Console Output

The run shows real-time status (`Created`, `Skipped`, `Deleted`, warnings) and ends with an elapsed-time summary.

```plaintext
---------------- Summary ----------------
Created: 12 | Updated: 3 | Deleted: 0 | Skipped: 8 | Failed: 0
Elapsed: 00:04:27
Reports: /tmp/IntuneHydrationKit/Reports/Hydration-Summary.md
JSON:    /tmp/IntuneHydrationKit/Reports/Hydration-Summary.json
----------------------------------------
```

### Log Files

Detailed logs are written to an OS-appropriate temp directory:

| OS | Log Path |
| ---- | ---------- |
| Windows | `$env:TEMP\IntuneHydrationKit\Logs\` |
| macOS | `/var/folders/.../IntuneHydrationKit/Logs/` |
| Linux | `/tmp/IntuneHydrationKit/Logs/` |

```plaintext
hydration-20241127-143052.log
```

### Summary Reports

After each run, reports are generated in the OS temp directory (same location as logs):

| OS | Reports Path |
| ---- | -------------- |
| Windows | `$env:TEMP\IntuneHydrationKit\Reports\` |
| macOS | `/var/folders/.../IntuneHydrationKit/Reports/` |
| Linux | `/tmp/IntuneHydrationKit/Reports/` |

- `Hydration-Summary.md` - Human-readable report
- `Hydration-Summary.json` - Machine-readable report

You can specify a custom output path using the `-ReportOutputPath` parameter or `reporting.outputPath` in settings.

---

## Troubleshooting

### Common Issues

#### "The term 'Invoke-MgGraphRequest' is not recognized"

```powershell
# Install required modules
Install-Module Microsoft.Graph.Authentication -Force
```

#### "Insufficient privileges"

- Use a Global Administrator account for Intune imports; PIM-elevated or non-Global Administrator accounts can be rejected by Intune Graph APIs
- Check that all required Graph permissions are consented

#### "No active Intune license found"

- Verify Intune licenses are assigned in the tenant
- Check for INTUNE_A, INTUNE_EDU, or EMS license

#### Objects not being deleted

- Verify the object has the `"Imported by Intune Hydration Kit"` marker; many resource types also use the `[IHD]` name prefix, while mobile apps and WinGet apps append ` - [IHD]`
- For CA policies, ensure the policy is in `disabled` state

## Project Structure

```plaintext
├── Public/                        # 19 exported functions
├── Private/                       # Internal helpers
├── Templates/                     # Bundled import templates
│   ├── CISBaselines/
│   ├── OpenIntuneBaseline/
│   ├── ConditionalAccess/
│   ├── DynamicGroups/
│   ├── Filters/
│   ├── StaticGroups/
│   ├── MobileApps/
│   └── Notifications/
├── Tests/                         # 67 Pester test files
├── docs/                          # MkDocs and PlatyPS reference docs
└── scripts/                       # Maintenance and assignment helpers
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes.

---

## Acknowledgments

- [OpenIntuneBaseline](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline) by SkipToTheEndpoint - Original community-driven Intune security baselines (this kit uses a [maintained fork](https://github.com/jorgeasaurus/OpenIntuneBaseline) for stability)
- [IntuneBaselines](https://github.com/jorgeasaurus/IntuneBaselines) by jorgeasaurus - Source repository for the bundled CIS benchmark-derived policy content included with this kit
- Microsoft Graph PowerShell SDK team

---

## Disclaimer

This tool is provided "as-is" without warranty of any kind. Always test in a non-production environment first. The authors are not responsible for any unintended changes to your Intune tenant. Review all configurations before enabling in production.
