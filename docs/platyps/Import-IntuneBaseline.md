---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-IntuneBaseline

## SYNOPSIS
Imports OpenIntuneBaseline policies from bundled templates

## SYNTAX

```
Import-IntuneBaseline [[-BaselinePath] <String>] [[-TenantId] <String>] [[-Platform] <String[]>]
 [[-ImportMode] <String>] [-RemoveExisting] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Imports OpenIntuneBaseline policies from the Templates/OpenIntuneBaseline directory.
Supports Settings Catalog, Device Configuration, Compliance, and Update policies.

## EXAMPLES

### EXAMPLE 1
```
Import-IntuneBaseline
```

### EXAMPLE 2
```
Import-IntuneBaseline -BaselinePath ./OpenIntuneBaseline -ImportMode SkipIfExists
```

### EXAMPLE 3
```
Import-IntuneBaseline -Platform Windows,macOS
```

## PARAMETERS

### -BaselinePath
Path to the OpenIntuneBaseline directory (defaults to Templates/OpenIntuneBaseline)

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

### -TenantId
Target tenant ID (uses connected tenant if not specified)

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
Filter baseline imports by platform.
Valid values: Windows, macOS, iOS, Android, All.
Defaults to 'All' which imports all baseline policies regardless of platform.
- Windows: Imports from WINDOWS/ and WINDOWS365/ folders
- macOS: Imports from MACOS/ folder
- iOS/Android: Imports from BYOD/ folder (app protection policies)

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

### -ImportMode
Import mode: SkipIfExists (default - skip policies that already exist)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: SkipIfExists
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
