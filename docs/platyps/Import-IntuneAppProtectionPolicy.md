---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-IntuneAppProtectionPolicy

## SYNOPSIS
Imports app protection (MAM) policies from templates

## SYNTAX

```
Import-IntuneAppProtectionPolicy [[-TemplatePath] <String>] [[-Platform] <String[]>] [-RemoveExisting]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Reads app protection templates and upserts Android/iOS managed app protection policies via Graph.

## EXAMPLES

### EXAMPLE 1
```
Import-IntuneAppProtectionPolicy
```

### EXAMPLE 2
```
Import-IntuneAppProtectionPolicy -Platform iOS
```

## PARAMETERS

### -TemplatePath
Path to the app protection template directory (defaults to Templates/AppProtection)

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
Valid values: iOS, Android, All.
Defaults to 'All' which imports all app protection templates regardless of platform.
Note: App protection policies only apply to iOS and Android platforms.

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
