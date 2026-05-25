---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Write-HydrationLog

## SYNOPSIS
Writes a log entry to the console and log file

## SYNTAX

```
Write-HydrationLog [-Message] <String> [[-Level] <String>] [[-Data] <Object>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Writes a timestamped, level-tagged log entry to both the console (with color-coded
icons) and the current session log file.
Used throughout the module to provide
consistent diagnostic output during hydration operations.

## EXAMPLES

### EXAMPLE 1
```
Write-HydrationLog -Message "Importing compliance policies" -Level Info
```

### EXAMPLE 2
```
Write-HydrationLog -Message "Rate limited by Graph API" -Level Warning
```

## PARAMETERS

### -Message
The message to log

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

### -Level
Log level (Info, Warning, Error, Debug)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: Info
Accept pipeline input: False
Accept wildcard characters: False
```

### -Data
Additional data to include

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
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
