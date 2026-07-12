---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Invoke-IntuneHydration

## SYNOPSIS
Main orchestrator function for Intune tenant hydration

## SYNTAX

### InteractiveTui
```
Invoke-IntuneHydration [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### SettingsFile
```
Invoke-IntuneHydration [-SettingsPath] <String> [-Delete] [-Force] [-Platform <String[]>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### ServicePrincipal
```
Invoke-IntuneHydration -TenantId <String> [-TenantName <String>] -ClientId <String>
 -ClientSecret <SecureString> [-Environment <String>] [-Create] [-Delete] [-Force] [-OpenIntuneBaseline]
 [-ComplianceTemplates] [-AppProtection] [-NotificationTemplates] [-EnrollmentProfiles] [-DynamicGroups]
 [-StaticGroups] [-DeviceFilters] [-ConditionalAccess] [-MobileApps] [-CISBaselines] [-All]
 [-Platform <String[]>] [-ReportOutputPath <String>] [-ReportFormats <String[]>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Interactive
```
Invoke-IntuneHydration -TenantId <String> [-TenantName <String>] [-Interactive] [-Environment <String>]
 [-Create] [-Delete] [-Force] [-OpenIntuneBaseline] [-ComplianceTemplates] [-AppProtection]
 [-NotificationTemplates] [-EnrollmentProfiles] [-DynamicGroups] [-StaticGroups] [-DeviceFilters]
 [-ConditionalAccess] [-MobileApps] [-CISBaselines] [-All] [-Platform <String[]>] [-ReportOutputPath <String>]
 [-ReportFormats <String[]>] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Executes the complete hydration workflow including authentication,
pre-flight checks, and import of all baseline configurations.

Three mutually exclusive invocation modes:
1.
Interactive TUI Mode: Call without arguments to launch the console wizard
2.
Settings File Mode: Use -SettingsPath to load all configuration from a JSON file
3.
Parameter Mode: Use -Interactive or -ClientId/-ClientSecret with other parameters

These modes cannot be mixed - choose one.

## EXAMPLES

### EXAMPLE 1
```
Invoke-IntuneHydration
```

Launch the interactive console wizard.
The TUI prompts for Azure cloud environment, operation mode, workload targets, platform filter, optional Graph consent prompting, verbose logging, and final confirmation. The tenant ID is discovered after browser sign-in.
Authentication uses interactive browser sign-in.

### EXAMPLE 2
```
Invoke-IntuneHydration `
	-SettingsPath ./settings.json
```

Run using settings from a JSON file.

### EXAMPLE 3
```
Invoke-IntuneHydration `
	-SettingsPath ./settings.json `
	-WhatIf
```

Dry-run using settings file.

### EXAMPLE 4
```
Invoke-IntuneHydration `
	-TenantId "00000000-0000-0000-0000-000000000000" `
	-Interactive `
	-Create `
	-All
```

Run with all imports enabled using interactive authentication.

### EXAMPLE 5
```
Invoke-IntuneHydration `
	-TenantId "00000000-0000-0000-0000-000000000000" `
	-ClientId "client-id" `
	-ClientSecret $secret `
	-Create `
	-ComplianceTemplates `
	-DynamicGroups
```

Run with service principal authentication and specific imports enabled.

### EXAMPLE 6
```
Invoke-IntuneHydration `
	-TenantId "00000000-0000-0000-0000-000000000000" `
	-Interactive `
	-Delete `
	-All `
	-WhatIf
```

Dry-run delete mode with interactive authentication.

## PARAMETERS

### -SettingsPath
Path to the settings JSON file.
Use this for settings file-based invocation.
Cannot be combined with -Interactive, -ClientId, or -ClientSecret.
Omit all parameters to launch the interactive TUI instead.

```yaml
Type: String
Parameter Sets: SettingsFile
Aliases:

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TenantId
Azure AD tenant ID (GUID format).
Required for parameter-based invocation.

```yaml
Type: String
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TenantName
Tenant name for display purposes (e.g., contoso.onmicrosoft.com)

```yaml
Type: String
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Interactive
Use interactive authentication (browser-based login).
Cannot be combined with -SettingsPath.

```yaml
Type: SwitchParameter
Parameter Sets: Interactive
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ClientId
Application (client) ID for service principal authentication.
Cannot be combined with -SettingsPath.

```yaml
Type: String
Parameter Sets: ServicePrincipal
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ClientSecret
Client secret for service principal authentication (SecureString).
Cannot be combined with -SettingsPath.

```yaml
Type: SecureString
Parameter Sets: ServicePrincipal
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Environment
Azure cloud environment.
Valid values: Global, USGov, USGovDoD, Germany, China

```yaml
Type: String
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: Global
Accept pipeline input: False
Accept wildcard characters: False
```

### -Create
Enable creation of configurations

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Delete
Enable deletion of kit-created configurations

```yaml
Type: SwitchParameter
Parameter Sets: SettingsFile, ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Force
Skip confirmation prompt when running in delete mode (available for both settings-file and parameter modes)

```yaml
Type: SwitchParameter
Parameter Sets: SettingsFile, ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -OpenIntuneBaseline
Process OpenIntuneBaseline policies

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ComplianceTemplates
Process compliance policy templates

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -AppProtection
Process app protection policies

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -NotificationTemplates
Process notification templates

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -EnrollmentProfiles
Process enrollment profiles (Autopilot, ESP)

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -DynamicGroups
Process dynamic groups

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -StaticGroups
Process static (assigned) groups

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -DeviceFilters
Process device filters

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ConditionalAccess
Process Conditional Access starter pack policies

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -MobileApps
Process mobile app templates

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -CISBaselines
Process bundled CIS baseline policies.

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -All
Enable all targets

```yaml
Type: SwitchParameter
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Platform
Filter imports by platform.
Valid values: Windows, macOS, iOS, Android, Linux, All.
Defaults to 'All' which imports resources for all platforms.
This affects: ComplianceTemplates, DeviceFilters, AppProtection, MobileApps, EnrollmentProfiles, OpenIntuneBaseline.
Cross-platform resources (DynamicGroups, StaticGroups, ConditionalAccess, NotificationTemplates) are not filtered.

```yaml
Type: String[]
Parameter Sets: SettingsFile, ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: @('All')
Accept pipeline input: False
Accept wildcard characters: False
```

### -ReportOutputPath
Output directory for reports

```yaml
Type: String
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ReportFormats
Report formats to generate (markdown, json)

```yaml
Type: String[]
Parameter Sets: ServicePrincipal, Interactive
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
Controls how progress updates are displayed during command execution.

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
