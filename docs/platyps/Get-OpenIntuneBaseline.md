---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Get-OpenIntuneBaseline

## SYNOPSIS
Downloads OpenIntuneBaseline repository from GitHub

## SYNTAX

```
Get-OpenIntuneBaseline [[-RepoUrl] <String>] [[-Branch] <String>] [[-DestinationPath] <String>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Downloads and extracts the OpenIntuneBaseline repository containing all baseline policies

## EXAMPLES

### EXAMPLE 1
```
Get-OpenIntuneBaseline -DestinationPath ./Baselines
```

## PARAMETERS

### -RepoUrl
GitHub repository URL (default: https://github.com/jorgeasaurus/OpenIntuneBaseline)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: Https://github.com/jorgeasaurus/OpenIntuneBaseline
Accept pipeline input: False
Accept wildcard characters: False
```

### -Branch
Branch to download (default: main)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: Main
Accept pipeline input: False
Accept wildcard characters: False
```

### -DestinationPath
Path to extract the repository (default: temp directory)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
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
