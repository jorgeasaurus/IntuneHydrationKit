---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-IntuneDeviceFilter

## SYNOPSIS
Creates device filters for Intune from templates

## SYNTAX

```
Import-IntuneDeviceFilter [[-TemplatePath] <String>] [[-Platform] <String[]>] [-RemoveExisting]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Reads JSON templates from Templates/Filters and creates device filters via Graph API.
Filters can be used to target or exclude devices from policy assignments.

## EXAMPLES

### EXAMPLE 1
```
Import-IntuneDeviceFilter
```

### EXAMPLE 2
```
Import-IntuneDeviceFilter -TemplatePath ./MyFilters
```

### EXAMPLE 3
```
Import-IntuneDeviceFilter -Platform Windows,macOS
```

## PARAMETERS

### -TemplatePath
Path to the filter template directory (defaults to Templates/Filters)

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
Valid values: Windows, macOS, iOS, Android, All.
Defaults to 'All' which imports all filter templates regardless of platform.
Note: Linux device filters are not currently supported by Intune.

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

### -RemoveExisting
If specified, removes existing filters created by this kit instead of creating new ones

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
