---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# New-IntuneDynamicGroup

## SYNOPSIS
Creates a dynamic Azure AD group for Intune

## SYNTAX

```
New-IntuneDynamicGroup [-DisplayName] <String> [[-Description] <String>] [-MembershipRule] <String>
 [[-MembershipRuleProcessingState] <String>] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Creates a dynamic group with the specified membership rule.
If a group with the same name exists, returns the existing group.

## EXAMPLES

### EXAMPLE 1
```
New-IntuneDynamicGroup -DisplayName "Windows 11 Devices" -MembershipRule "(device.operatingSystem -eq 'Windows') and (device.operatingSystemVersion -startsWith '10.0.22')"
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

### -MembershipRule
OData membership rule for dynamic membership

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -MembershipRuleProcessingState
Processing state for the rule (On or Paused)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: On
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
