---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Test-IntunePrerequisites

## SYNOPSIS
Validates Intune tenant prerequisites

## SYNTAX

```
Test-IntunePrerequisites [[-RequiredScopes] <String[]>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Checks for Intune license availability, Azure AD Premium P2 license (for risk-based
Conditional Access), and required Microsoft Graph permission scopes.

Non-blocking notes are emitted when Premium P2 is not found, as certain Conditional
Access policies that use sign-in risk or user risk conditions require this license level.

## EXAMPLES

### EXAMPLE 1
```
Test-IntunePrerequisites
```

## PARAMETERS

### -RequiredScopes
Microsoft Graph permission scopes required for prerequisite validation.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: @(Get-HydrationGraphScopes -Profile Hydration)
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
