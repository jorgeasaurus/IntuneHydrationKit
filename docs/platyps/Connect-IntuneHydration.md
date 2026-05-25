---
external help file: IntuneHydrationKit-help.xml
Module Name: IntuneHydrationKit
online version:
schema: 2.0.0
---

# Connect-IntuneHydration

## SYNOPSIS
Connects to Microsoft Graph with required scopes for Intune hydration

## SYNTAX

### Interactive (Default)
```
Connect-IntuneHydration -TenantId <String> [-Interactive] [-Environment <String>] [-ScopeProfile <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### ClientSecret
```
Connect-IntuneHydration -TenantId <String> -ClientId <String> -ClientSecret <SecureString>
 [-Environment <String>] [-ScopeProfile <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Establishes authentication to Microsoft Graph using interactive or client secret auth.
Supports multiple cloud environments: Global (Commercial), USGov, USGovDoD, Germany, China.

## EXAMPLES

### EXAMPLE 1
```
Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive
```

### EXAMPLE 2
```
Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -ClientId "app-id" -ClientSecret $secret
```

### EXAMPLE 3
```
Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive -Environment USGov
```

## PARAMETERS

### -TenantId
The Azure AD tenant ID (GUID format)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ClientId
Application (client) ID for app registration auth

```yaml
Type: String
Parameter Sets: ClientSecret
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ClientSecret
Client secret for authentication (use SecureString for production)

```yaml
Type: SecureString
Parameter Sets: ClientSecret
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Interactive
Use interactive authentication

```yaml
Type: SwitchParameter
Parameter Sets: Interactive
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Environment
Graph environment: Global, USGov, USGovDoD, Germany, China

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Global
Accept pipeline input: False
Accept wildcard characters: False
```

### -ScopeProfile
Scope profile used for interactive delegated auth.
Hydration requests full kit scopes;
ConditionalAccess requests a narrower CA-focused scope set.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Hydration
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
