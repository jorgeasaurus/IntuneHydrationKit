---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-HydrationSettings

## SYNOPSIS
Imports and validates hydration settings

## SYNTAX

```
Import-HydrationSettings [-Path] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Loads settings from a JSON file.

## EXAMPLES

### EXAMPLE 1
```
Import-HydrationSettings -Path './settings.json'
```

### EXAMPLE 2
```
$settings = Import-HydrationSettings -Path './settings.json'
$settings.tenant.tenantId  # Access tenant ID from loaded settings
```

## PARAMETERS

### -Path
Path to the settings file

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
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
