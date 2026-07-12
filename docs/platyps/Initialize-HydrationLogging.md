---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Initialize-HydrationLogging

## SYNOPSIS
Initializes logging for the hydration session

## SYNTAX

```
Initialize-HydrationLogging [[-LogPath] <String>] [-EnableVerbose] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Sets up the logging infrastructure for a hydration run, creating the log directory
and session log file.
Configures both console and file logging with timestamps.

## EXAMPLES

### EXAMPLE 1
```
Initialize-HydrationLogging
# Uses default temp path: $env:TEMP/IntuneHydrationKit/Logs (Windows) or /tmp/IntuneHydrationKit/Logs (macOS/Linux)
```

### EXAMPLE 2
```
Initialize-HydrationLogging -LogPath "./MyLogs"
# Uses custom path
```

## PARAMETERS

### -LogPath
Path to write log files.
Defaults to OS temp directory under IntuneHydrationKit/Logs

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

### -EnableVerbose
Enable verbose logging

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
