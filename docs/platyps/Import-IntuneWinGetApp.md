---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-IntuneWinGetApp

## SYNOPSIS
Imports WinGet-backed Win32 apps from bundled catalog or preset templates.

## SYNTAX

```
Import-IntuneWinGetApp [[-TemplateId] <String[]>] [[-PresetId] <String>] [-RemoveExisting]
 [[-WorkingDirectory] <String>] [-RemediationEnabled] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Creates Intune Win32 apps that wrap WinGet install and uninstall commands,
publishes the generated .intunewin content, and tags created apps with both
the hydration marker and WinGet ownership metadata so future deletes are safe.

## EXAMPLES

### EXAMPLE 1
```
Import-IntuneWinGetApp -PresetId 'starter-pack'
```

### EXAMPLE 2
```
Import-IntuneWinGetApp -TemplateId 'google-chrome'
```

### EXAMPLE 3
```
Import-IntuneWinGetApp -RemoveExisting -PresetId 'starter-pack'
```

## PARAMETERS

### -TemplateId
One or more specific bundled WinGet template IDs to import.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PresetId
Optional preset ID to resolve from Templates/MobileApps/Windows/WinGet/Presets.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RemoveExisting
Deletes matching WinGet hydration-owned Win32 apps instead of creating them.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -WorkingDirectory
Directory used to stage wrapper scripts, packages, and upload artifacts.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

New app requests should be opened as an issue or submitted as a PR that adds a bundled template with resolved package metadata.

### -RemediationEnabled
When enabled, creates or updates proactive remediation scripts for the selected
WinGet app set.
A system-scoped script is generated for machine apps and a
user-scoped script is generated for user apps.
No assignments are created.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
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

### System.Management.Automation.PSObject[]
## NOTES

## RELATED LINKS
