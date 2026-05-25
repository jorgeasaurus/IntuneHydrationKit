# Invocation Examples

## Parameter Mode

### Available Parameters

Use `Get-Help Invoke-IntuneHydration -Detailed` for the live source of truth. The table below lists the full parameter surface for parameter mode.

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
| `-WhatIf` | Preview changes without applying them |
| `-Verbose` | Emit verbose diagnostics |

### Preview First

```powershell
Invoke-IntuneHydration `
    -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -All `
    -WhatIf
```

### Run Specific Targets

```powershell
Invoke-IntuneHydration `
    -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -ComplianceTemplates `
    -DynamicGroups `
    -DeviceFilters
```

### Platform-Specific Run

```powershell
Invoke-IntuneHydration `
    -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -All `
    -Platform Windows, macOS
```

### All Minus CIS Baseline

```powershell
Invoke-IntuneHydration `
    -TenantId "your-tenant-id" `
    -Interactive `
    -OpenIntuneBaseline `
    -CISBaselines `
    -ComplianceTemplates `
    -AppProtection `
    -NotificationTemplates `
    -EnrollmentProfiles `
    -DynamicGroups `
    -StaticGroups `
    -DeviceFilters `
    -ConditionalAccess `
    -MobileApps
```

### Service Principal Authentication

```powershell
$secret = ConvertTo-SecureString "your-secret" -AsPlainText -Force

Invoke-IntuneHydration `
    -TenantId "your-tenant-id" `
    -ClientId "app-id" `
    -ClientSecret $secret `
    -Create `
    -All
```

### Windows Mobile Apps Only

```powershell
Invoke-IntuneHydration `
    -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -MobileApps `
    -Platform Windows `
    -WhatIf

Invoke-IntuneHydration `
    -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -MobileApps `
    -Platform Windows
```

## Settings File Mode

### Create the File

```powershell
Copy-Item settings.example.json settings.json
```

### Preview and Run

```powershell
Invoke-IntuneHydration `
    -SettingsPath ./settings.json `
    -WhatIf

Invoke-IntuneHydration `
    -SettingsPath ./settings.json
```

### Settings File Details

Supported authentication methods:

| Method        | Use Case             | Requirements                        |
| ------------- | -------------------- | ----------------------------------- |
| Interactive   | Manual runs, testing | Global Administrator recommended    |
| Client Secret | Automation, CI/CD    | App registration with client secret |

For community support, run interactive hydration with a Global Administrator account. PIM-elevated or non-Global Administrator accounts can fail Intune Graph authorization even when Graph scopes are present because Intune performs its own service authorization after Graph authentication.

Interactive (recommended for manual runs):

```json
"authentication": {
    "mode": "interactive",
    "environment": "Global"
}
```

Client Secret (recommended for automation):

```json
"authentication": {
    "mode": "clientSecret",
    "clientId": "00000000-0000-0000-0000-000000000000",
    "clientSecret": "your-client-secret-value",
    "environment": "Global"
}
```

Store client secrets securely (for example, Azure Key Vault or environment-injected values).

Supported cloud environments:

| Environment | Description                       |
| ----------- | --------------------------------- |
| `Global`    | Commercial/Public cloud (default) |
| `USGov`     | US Government (GCC High)          |
| `USGovDoD`  | US Government (DoD)               |
| `Germany`   | Germany sovereign cloud           |
| `China`     | China sovereign cloud (21Vianet)  |

Operation modes:

| Option   | Description                                          |
| -------- | ---------------------------------------------------- |
| `dryRun` | Preview changes without applying (same as `-WhatIf`) |
| `create` | Create new configurations                            |
| `delete` | Delete existing kit-created configurations           |
| `force`  | Skip confirmation prompt when running delete mode    |

Create mode:

```json
"options": {
    "create": true,
    "delete": false
}
```

Delete mode:

```json
"options": {
    "create": false,
    "delete": true,
    "force": false
}
```

### Selective Targets

Enable only the categories you need:

```json
"imports": {
    "openIntuneBaseline": true,
    "cisBaselines": true,
    "complianceTemplates": true,
    "appProtection": true,
    "notificationTemplates": true,
    "enrollmentProfiles": true,
    "dynamicGroups": true,
    "staticGroups": true,
    "deviceFilters": true,
    "conditionalAccess": true,
    "mobileApps": true
}
```

### Windows WinGet App Catalog

Windows mobile app hydration imports the full bundled Windows catalog by default:

```json
"mobileApps": {
    "templateIds": [],
    "remediation": {
        "enabled": true
    }
}
```

Only bundled WinGet templates are supported. To add another app, open a request issue or submit a PR that adds the template.

### Platform Filtering

```json
"platforms": ["Windows", "macOS"]
```

**Available platforms:** `Windows`, `macOS`, `iOS`, `Android`, `Linux`, `All`

**Default:** `["All"]` (imports resources for all platforms)

**Affected resources:**

- OpenIntuneBaseline policies
- CIS baseline policies
- Compliance policies
- App Protection policies
- Device Filters
- Mobile Apps
- Enrollment Profiles

**Cross-platform resources (not filtered):**

- Dynamic Groups
- Static Groups
- Conditional Access policies
- Notification Templates

**Examples:**

```json
// Windows-only deployment
"platforms": ["Windows"]

// Windows and macOS
"platforms": ["Windows", "macOS"]

// Mobile platforms only
"platforms": ["iOS", "Android"]

// All platforms (default)
"platforms": ["All"]
```

### Minimal Settings Example

```json
{
  "tenant": {
    "tenantId": "your-tenant-id-here",
    "tenantName": "yourtenant.onmicrosoft.com"
  },
  "authentication": {
    "mode": "interactive"
  },
  "options": {
    "dryRun": false,
    "create": true,
    "delete": false,
    "force": false
  }
}
```

### Debug Mode

Enable verbose logging in settings:

```json
"options": {
    "verbose": true
}
```

## Cloned Repository

Use the same commands above with the wrapper script:

```powershell
./Invoke-IntuneHydration.ps1
```

## WinGet App Templates

By default, `mobileApps` with `Windows` imports the full bundled Windows catalog. To import only specific bundled WinGet-backed apps, provide template IDs:

```json
{
  "imports": {
    "mobileApps": true
  },
  "mobileApps": {
    "templateIds": ["google-chrome", "visual-studio-code"]
  },
  "platforms": ["Windows"]
}
```

Leave `mobileApps.templateIds` empty, or omit `mobileApps`, to import the full catalog. Use `mobileApps.presetId` to import a bundled preset such as `starter-pack` or `mobile-apps`. New apps should be requested in an issue or added by PR.