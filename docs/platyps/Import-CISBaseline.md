---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Import-CISBaseline

## SYNOPSIS
Imports CIS Baseline policies from bundled templates

## SYNTAX

```
Import-CISBaseline [[-BaselinePath] <String>] [[-TenantId] <String>] [[-Platform] <String[]>]
 [[-ImportMode] <String>] [-RemoveExisting] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Imports CIS Benchmark and industry baseline policies from the Templates/CISBaselines directory.
Supports Settings Catalog, Compliance, and Device Configuration policies.
Routes each policy to the correct Graph API endpoint based on its @odata.type property.

## EXAMPLES

### EXAMPLE 1
```
Import-CISBaseline
```

### EXAMPLE 2
```
Import-CISBaseline -Platform Windows
```

### EXAMPLE 3
```
Import-CISBaseline -RemoveExisting
```

## PARAMETERS

### -BaselinePath
Path to the CISBaselines directory (defaults to Templates/CISBaselines)

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
Filter imports by platform.
Valid values: Windows, macOS, iOS, Android, Linux, All.
Defaults to 'All'.
Filters based on the 'platforms' property inside each JSON policy.

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
Delete existing CIS baseline policies created by this kit instead of importing

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
