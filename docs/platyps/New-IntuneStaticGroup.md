---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# New-IntuneStaticGroup

## SYNOPSIS
Creates a static Azure AD security group for Intune

## SYNTAX

```
New-IntuneStaticGroup [-DisplayName] <String> [[-Description] <String>] [-RequiresServicePrincipalOwner]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Creates a static (assigned) security group.
If a group with the same name exists, returns the existing group.
For Autopilot device preparation groups, adds the Intune Provisioning Client as owner.

## EXAMPLES

### EXAMPLE 1
```
New-IntuneStaticGroup -DisplayName "Intune - Update Ring Pilot Users" -Description "Users for pilot ring"
```

### EXAMPLE 2
```
New-IntuneStaticGroup -DisplayName "Windows Autopilot device preparation" -RequiresServicePrincipalOwner
```

## PARAMETERS

### -DisplayName
The display name for the group

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

### -Description
Description of the group

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

### -RequiresServicePrincipalOwner
If set, adds the Intune Provisioning Client service principal as owner (required for Autopilot device preparation)

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
