---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-IntuneCompliancePolicy

## SYNOPSIS
Imports device compliance policies from templates

## SYNTAX

```
Import-IntuneCompliancePolicy [[-TemplatePath] <String>] [[-Platform] <String[]>] [-RemoveExisting]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Reads JSON templates from Templates/Compliance and creates compliance policies via Graph.

## EXAMPLES

### EXAMPLE 1
```
Import-IntuneCompliancePolicy
```

### EXAMPLE 2
```
Import-IntuneCompliancePolicy -Platform Windows,macOS
```

## PARAMETERS

### -TemplatePath
Path to the compliance template directory (defaults to Templates/Compliance)

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
Valid values: Windows, macOS, iOS, Android, Linux, All.
Defaults to 'All' which imports all compliance templates regardless of platform.

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
