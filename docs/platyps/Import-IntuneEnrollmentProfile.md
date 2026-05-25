---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-IntuneEnrollmentProfile

## SYNOPSIS
Imports enrollment profiles

## SYNTAX

```
Import-IntuneEnrollmentProfile [[-TemplatePath] <String>] [[-DeviceNameTemplate] <String>]
 [[-Platform] <String[]>] [-RemoveExisting] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Creates Windows Autopilot deployment profiles and Enrollment Status Page configurations.
Optionally creates Apple enrollment profiles if ABM is enabled.

## EXAMPLES

### EXAMPLE 1
```
Import-IntuneEnrollmentProfile
```

### EXAMPLE 2
```
Import-IntuneEnrollmentProfile -Platform Windows
```

## PARAMETERS

### -TemplatePath
Path to the enrollment template directory

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

### -DeviceNameTemplate
Custom device naming template (default: %SERIAL%)

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

### -Platform
Filter templates by platform.
Valid values: Windows, macOS, All.
Defaults to 'All' which imports all enrollment profile templates regardless of platform.
Note: Enrollment profiles are available for Windows (Autopilot, ESP) and macOS (DEP).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: @('All')
Accept pipeline input: False
Accept wildcard characters: False
```

### -RemoveExisting
If specified, removes existing objects created by this kit instead of importing new ones.

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
