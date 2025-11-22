# Intune Configuration Files

This directory contains baseline configuration files for Microsoft Intune that can be imported into any supported tenant type.

## Directory Structure

```
Configurations/
├── CompliancePolicies/        # Device compliance policies
├── ConfigurationProfiles/     # Configuration profiles for various settings
├── DeviceConfigurations/      # Device-specific configurations
├── DynamicGroups/            # Azure AD dynamic group definitions
└── SecurityBaselines/        # Security baseline configurations
```

## Configuration Types

### Compliance Policies

Compliance policies define the requirements devices must meet to be considered compliant. Non-compliant devices can be blocked from accessing corporate resources.

**Available Compliance Policies:**
- `Windows10-BaselineCompliance.json` - Windows 10/11 baseline compliance
- `iOS-BaselineCompliance.json` - iOS/iPadOS baseline compliance
- `Android-BaselineCompliance.json` - Android baseline compliance
- `macOS-BaselineCompliance.json` - macOS baseline compliance

**Key Features:**
- Password requirements
- OS version requirements
- Encryption requirements
- Security feature requirements (BitLocker, Secure Boot, etc.)
- Device health attestation

### Configuration Profiles

Configuration profiles deploy settings to devices including email, Wi-Fi, VPN, certificates, and restrictions.

**Profile Types:**
- Email configuration profiles
- Wi-Fi profiles
- VPN profiles
- Certificate profiles
- Device restriction profiles

### Device Configurations

Device configurations control device features and capabilities.

**Configuration Types:**
- Endpoint protection settings
- Windows Update policies
- Kiosk mode configurations
- Browser settings

### Dynamic Groups

Dynamic groups automatically manage membership based on device or user attributes.

**Available Dynamic Groups:**
- `AllWindowsDevices.json` - All Windows 10/11 devices
- `AlliOSDevices.json` - All iOS/iPadOS devices
- `AllAndroidDevices.json` - All Android devices
- `AllmacOSDevices.json` - All macOS devices
- `IntuneEnrolledDevices.json` - All Intune enrolled devices
- `CorporateOwnedDevices.json` - Corporate owned devices only

**Benefits:**
- Automatic membership management
- No manual user/device addition
- Real-time updates
- Policy targeting by device type

### Security Baselines

Security baselines provide pre-configured security settings based on Microsoft security recommendations.

**Baseline Types:**
- Windows 10/11 security baseline
- Microsoft Edge security baseline
- Microsoft Defender for Endpoint baseline

## Tenant-Specific Configurations

You can create tenant-specific configurations by creating subfolders for each tenant type:

```
Configurations/
├── CompliancePolicies/
│   ├── Windows10-BaselineCompliance.json     # Applies to all tenants
│   ├── Commercial/
│   │   └── Windows10-CommercialCompliance.json
│   ├── GCC/
│   │   └── Windows10-GCCCompliance.json
│   ├── GCCHigh/
│   │   └── Windows10-GCCHighCompliance.json
│   └── DoD/
│       └── Windows10-DoDCompliance.json
```

The hydration script will automatically use tenant-specific configurations when available, falling back to the base configuration if a tenant-specific version doesn't exist.

## Customizing Configurations

### Basic Customization

1. **Copy the baseline file:**
   ```powershell
   Copy-Item "CompliancePolicies\Windows10-BaselineCompliance.json" `
             "CompliancePolicies\Windows10-CustomCompliance.json"
   ```

2. **Edit the JSON file:**
   ```powershell
   notepad "CompliancePolicies\Windows10-CustomCompliance.json"
   ```

3. **Modify the displayName and settings as needed**

### Tenant-Specific Customization

For government tenants, you may need stricter security requirements:

**GCC High Example:**
```json
{
  "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
  "displayName": "Windows 10 - GCC High Compliance",
  "description": "Enhanced compliance for GCC High environment",
  "passwordRequired": true,
  "passwordMinimumLength": 14,
  "passwordRequiredType": "alphanumeric",
  "passwordMinutesOfInactivityBeforeLock": 10,
  "passwordExpirationDays": 60,
  "passwordPreviousPasswordBlockCount": 24,
  "bitLockerEnabled": true,
  "secureBootEnabled": true,
  "codeIntegrityEnabled": true,
  "tpmRequired": true
}
```

**DoD Example:**
```json
{
  "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
  "displayName": "Windows 10 - DoD IL5 Compliance",
  "description": "Maximum security compliance for DoD IL5",
  "passwordRequired": true,
  "passwordMinimumLength": 15,
  "passwordRequiredType": "alphanumeric",
  "passwordMinutesOfInactivityBeforeLock": 5,
  "passwordExpirationDays": 60,
  "passwordPreviousPasswordBlockCount": 24,
  "bitLockerEnabled": true,
  "secureBootEnabled": true,
  "codeIntegrityEnabled": true,
  "tpmRequired": true,
  "earlyLaunchAntiMalwareDriverEnabled": true,
  "rtpEnabled": true
}
```

## JSON File Format

All configuration files use standard Microsoft Graph API JSON format.

### Required Properties

Most configurations require:
- `@odata.type` - The type of configuration
- `displayName` - User-friendly name
- `description` - Description of the configuration

### Removing Auto-Generated Properties

When exporting configurations from an existing tenant, remove these properties:
- `id` - Auto-generated by Intune
- `createdDateTime` - Auto-generated timestamp
- `lastModifiedDateTime` - Auto-generated timestamp
- `version` - Version tracking

Example cleanup:
```powershell
# Read configuration
$Config = Get-Content "exported-config.json" | ConvertFrom-Json

# Remove auto-generated properties
$Config.PSObject.Properties.Remove('id')
$Config.PSObject.Properties.Remove('createdDateTime')
$Config.PSObject.Properties.Remove('lastModifiedDateTime')

# Save cleaned configuration
$Config | ConvertTo-Json -Depth 10 | Out-File "cleaned-config.json"
```

## Validation

Validate your JSON files before importing:

```powershell
# Validate JSON syntax
try {
    $Config = Get-Content "CompliancePolicies\MyPolicy.json" | ConvertFrom-Json
    Write-Host "Valid JSON" -ForegroundColor Green
}
catch {
    Write-Host "Invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
}

# Check required properties
if ($Config.displayName -and $Config.'@odata.type') {
    Write-Host "Required properties present" -ForegroundColor Green
}
else {
    Write-Host "Missing required properties" -ForegroundColor Red
}
```

## Exporting Configurations from Existing Tenant

To export configurations from an existing Intune tenant:

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"

# Export compliance policies
$Policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies"

foreach ($Policy in $Policies.value) {
    $FileName = "$($Policy.displayName -replace '[^a-zA-Z0-9]', '-').json"
    
    # Remove auto-generated properties
    $Policy.PSObject.Properties.Remove('id')
    $Policy.PSObject.Properties.Remove('createdDateTime')
    $Policy.PSObject.Properties.Remove('lastModifiedDateTime')
    
    # Save to file
    $Policy | ConvertTo-Json -Depth 10 | Out-File "CompliancePolicies\$FileName"
}
```

## Best Practices

### Configuration Naming

- Use descriptive names: `Windows10-BaselineCompliance.json`
- Include platform: `iOS-`, `Android-`, `Windows10-`
- Include purpose: `-Baseline`, `-Enhanced`, `-Pilot`
- No special characters in filenames

### Security Considerations

- Review all settings before importing
- Test in non-production environment first
- Document any customizations
- Version control configuration files
- Never include secrets or credentials

### Maintenance

- Review configurations quarterly
- Update for new OS versions
- Test compatibility before importing
- Keep backups of working configurations
- Document changes in git commits

### Testing Strategy

1. **Validate JSON syntax** using PowerShell or online validators
2. **Test in dev/test environment** before production
3. **Use WhatIf parameter** to preview changes
4. **Start with pilot groups** for gradual rollout
5. **Monitor compliance reports** after deployment

## Troubleshooting

### Common Issues

**Invalid JSON:**
- Ensure proper formatting with commas and brackets
- Use a JSON validator or linter
- Check for trailing commas (not allowed in JSON)

**Missing Properties:**
- Ensure `@odata.type` is present and correct
- Include required properties like `displayName`
- Check Microsoft Graph documentation for required fields

**Import Failures:**
- Check Graph API permissions
- Verify configuration is appropriate for tenant type
- Review log files for detailed error messages

### Getting Help

- Review Microsoft Graph API documentation
- Check Intune documentation for policy details
- Use Microsoft Graph Explorer for testing
- Consult the main [README.md](../README.md) and [EXAMPLES.md](../EXAMPLES.md)

## Resources

- [Microsoft Graph API - Device Management](https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview)
- [Intune Compliance Policies](https://docs.microsoft.com/en-us/mem/intune/protect/device-compliance-get-started)
- [Dynamic Group Membership Rules](https://docs.microsoft.com/en-us/azure/active-directory/enterprise-users/groups-dynamic-membership)
- [Security Baselines](https://docs.microsoft.com/en-us/mem/intune/protect/security-baselines)

## Contributing

To contribute new baseline configurations:

1. Export from a working Intune environment
2. Remove auto-generated properties
3. Test with validation script
4. Document the configuration purpose
5. Submit a pull request with clear description
