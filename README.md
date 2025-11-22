# Intune Hydration Kit

PowerShell module to stand up an Intune tenant with best-practice defaults. One script run; it creates groups, filters, compliance/app protection policies, enrollment, notification templates, and a disabled Conditional Access starter pack.

## Quick Start
1) **Install prerequisites (PowerShell 7+)**
```powershell
Install-Module Microsoft.Graph.Authentication,Microsoft.Graph.Groups,Microsoft.Graph.Identity.SignIns,Microsoft.Graph.DeviceManagement -Scope CurrentUser
```
2) **Clone and configure**
```powershell
git clone https://github.com/yourusername/Intune-Hydration-Kit.git
cd Intune-Hydration-Kit
Copy-Item settings.example.json settings.json
# edit settings.json -> tenantId, tenantName, auth mode (interactive/certificate)
```
3) **Run**
```powershell
# Dry-run
pwsh ./Scripts/Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -WhatIf
# Live
pwsh ./Scripts/Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json
```

## What Gets Imported
- **Baseline policies**: Full OpenIntuneBaseline (Settings Catalog where possible), skips IntuneManagement-only exports.
- **Compliance templates** (local `Templates/Compliance/`):
  - Windows: standard + custom script-based policy (requires script/rules IDs).
  - Android: Basic and Strict.
  - iOS: Basic and Strict.
  - macOS: Basic and Strict.
  - Linux: Basic and Strict (linuxMdm).
- **App protection (MAM)**: Android and iOS templates in `Templates/AppProtection/`.
- **Notification templates**: e.g., First Alert with localized message.
- **Dynamic groups**: OS, manufacturer, Autopilot, compliance-state.
- **Device filters**: 12 manufacturer/model filters across OSes.
- **Enrollment**: Windows Autopilot deployment profile + ESP.
- **Conditional Access**: 14 starter policies, all created DISABLED.
- **Reports**: Markdown and JSON summary under `Reports/`.

## Settings (minimal example)
```json
{
  "tenant": { "tenantId": "00000000-0000-0000-0000-000000000000", "tenantName": "contoso.onmicrosoft.com" },
  "authentication": { "mode": "interactive", "environment": "Global" },
  "imports": {
    "openIntuneBaseline": true,
    "complianceTemplates": true,
    "appProtection": true,
    "notificationTemplates": true,
    "enrollmentProfiles": true,
    "dynamicGroups": true,
    "conditionalAccess": true
  }
}
```

## Requirements
- PowerShell 7+
- Graph permissions: `DeviceManagementConfiguration.ReadWrite.All`, `DeviceManagementServiceConfig.ReadWrite.All`, `DeviceManagementManagedDevices.ReadWrite.All`, `Group.ReadWrite.All`, `Policy.ReadWrite.ConditionalAccess`, `Directory.ReadWrite.All`.

## Outputs
- Console + `Logs/` for progress.
- `Reports/Hydration-Summary.md` and `Reports/Hydration-Summary.json` for counts and details.

## Notes
- Conditional Access policies are **disabled** by default; enable after review.
- IntuneManagement-only OIB exports are skipped (require Windows GUI tool).
- Custom Windows compliance template includes placeholders (`REPLACE_SCRIPT_ID`, `REPLACE_RULES_BASE64`)—set real values before use.
