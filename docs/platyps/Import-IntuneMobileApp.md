---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-IntuneMobileApp

## SYNOPSIS
Imports mobile apps from JSON templates

## SYNTAX

```
Import-IntuneMobileApp [[-TemplatePath] <String>] [[-Platform] <String[]>] [[-TemplateId] <String[]>]
 [-RemoveExisting] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Reads JSON templates from Templates/MobileApps and creates mobile apps via Graph API.
Mobile apps append " - \[IHD\]" to their template display names and use the
notes field hydration marker for ownership and deletion safety.

## EXAMPLES

### EXAMPLE 1
```
Import-IntuneMobileApp
```

### EXAMPLE 2
```
Import-IntuneMobileApp -RemoveExisting
```

### EXAMPLE 3
```
Import-IntuneMobileApp -Platform Windows
```

### EXAMPLE 4
```
Import-IntuneMobileApp -Platform Windows -TemplateId 'CompanyPortal', 'WhatsApp'
```

## PARAMETERS

### -TemplatePath
Path to the mobile apps template directory (defaults to Templates/MobileApps)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Platform
Filter templates by platform.
Valid values: Windows, macOS, All.
Defaults to 'All' which imports all mobile app templates regardless of platform.
Note: Mobile app templates are organized by Windows and macOS directories.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: @('All')
Accept pipeline input: False
Accept wildcard characters: False
```

### -TemplateId
Optional mobile app template file names to include (without the .json extension).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RemoveExisting
If specified, removes existing mobile apps that were created by Intune Hydration Kit

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

## NOTES

## RELATED LINKS
