# Intune Hydration Kit

A PowerShell-based toolkit for quickly importing baseline Intune configurations into Microsoft 365 tenants. Supports Commercial, GCC, GCC High, and DoD tenant environments.

## Features

- **Multi-Tenant Support**: Works with Commercial, GCC, GCC High, and DoD Microsoft 365 tenants
- **Comprehensive Baselines**: Includes compliance policies, configuration profiles, and dynamic groups
- **Tenant-Specific Endpoints**: Automatically configures Microsoft Graph API endpoints based on tenant type
- **Security Compliance**: Built with government cloud security requirements in mind
- **Flexible Import Options**: Import all configurations or select specific types
- **Detailed Logging**: Comprehensive logging for auditing and troubleshooting

## Prerequisites

- PowerShell 5.1 or PowerShell 7+
- Microsoft.Graph PowerShell SDK modules:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- Administrative permissions in the target Intune tenant
- Network access to the appropriate Microsoft Graph endpoint for your tenant type

## Tenant Type Requirements

### Commercial
- Standard Microsoft 365 subscription
- No special network requirements

### GCC (Government Community Cloud)
- FedRAMP Moderate authorization required
- Access from approved government networks recommended

### GCC High (Government Community Cloud High)
- FedRAMP High authorization required
- **US Person** status required
- Must connect from US Government network or approved VPN
- Suitable for CUI (Controlled Unclassified Information) and ITAR data

### DoD (Department of Defense)
- DoD IL5 authorization required
- Active security clearance required
- Must connect from DoD network infrastructure
- Suitable for classified data up to IL5

## Quick Start

1. **Clone or download this repository:**
   ```powershell
   git clone https://github.com/jorgeasaurus/Intune-Hydration-Kit.git
   cd Intune-Hydration-Kit
   ```

2. **Run the hydration script:**
   ```powershell
   # For Commercial tenants
   .\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "your-tenant-id-here"
   
   # For GCC High tenants
   .\Start-IntuneHydration.ps1 -TenantType GCCHigh -TenantId "your-tenant-id-here"
   
   # For DoD tenants
   .\Start-IntuneHydration.ps1 -TenantType DoD -TenantId "your-tenant-id-here"
   ```

3. **Authenticate when prompted** with credentials that have Intune Administrator privileges

4. **Review the results** in the console and log files

## Usage

### Basic Usage

```powershell
.\Start-IntuneHydration.ps1 -TenantType <TenantType> -TenantId <TenantId>
```

### Parameters

- **TenantType** (Required): The type of Microsoft 365 tenant
  - Valid values: `Commercial`, `GCC`, `GCCHigh`, `DoD`
  - Default: `Commercial`

- **TenantId** (Required): Your Azure AD Tenant ID (GUID format)

- **ConfigurationPath** (Optional): Custom path to configuration files
  - Default: `./Configurations`

- **ImportAll** (Optional): Import all available configurations without prompting

- **WhatIf** (Optional): Preview what would be imported without making changes

### Examples

**Import all configurations to a Commercial tenant:**
```powershell
.\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "12345678-1234-1234-1234-123456789012" -ImportAll
```

**Preview what would be imported to a GCC High tenant:**
```powershell
.\Start-IntuneHydration.ps1 -TenantType GCCHigh -TenantId "12345678-1234-1234-1234-123456789012" -WhatIf
```

**Use custom configuration path:**
```powershell
.\Start-IntuneHydration.ps1 -TenantType DoD -TenantId "12345678-1234-1234-1234-123456789012" -ConfigurationPath "C:\CustomConfigs"
```

For more detailed examples, see [EXAMPLES.md](EXAMPLES.md).

## Configuration Files

The toolkit includes baseline configurations organized by type:

- **Compliance Policies**: `/Configurations/CompliancePolicies/`
  - Windows 10/11 baseline compliance
  - iOS/iPadOS baseline compliance
  - Android baseline compliance

- **Configuration Profiles**: `/Configurations/ConfigurationProfiles/`
  - Device restriction policies
  - Email and Wi-Fi profiles
  - Certificate deployment profiles

- **Device Configurations**: `/Configurations/DeviceConfigurations/`
  - Endpoint protection settings
  - Windows Update policies
  - Kiosk mode configurations

- **Dynamic Groups**: `/Configurations/DynamicGroups/`
  - Platform-specific device groups
  - Conditional access groups

- **Security Baselines**: `/Configurations/SecurityBaselines/`
  - Windows security baselines
  - Microsoft Edge security baseline
  - Microsoft Defender for Endpoint baseline

### Tenant-Specific Configurations

You can create tenant-specific configuration folders for any configuration type. The script will automatically use tenant-specific configurations when available:

```
Configurations/
├── CompliancePolicies/
│   ├── Windows10-BaselineCompliance.json (applies to all tenants)
│   ├── GCCHigh/
│   │   └── Windows10-GCCHighCompliance.json (GCC High only)
│   └── DoD/
│       └── Windows10-DoDCompliance.json (DoD only)
```

## Microsoft Graph API Endpoints

The toolkit automatically configures the correct Microsoft Graph endpoints:

| Tenant Type | Graph Endpoint | Login Endpoint |
|-------------|---------------|----------------|
| Commercial | `https://graph.microsoft.com` | `https://login.microsoftonline.com` |
| GCC | `https://graph.microsoft.com` | `https://login.microsoftonline.com` |
| GCC High | `https://graph.microsoft.us` | `https://login.microsoftonline.us` |
| DoD | `https://dod-graph.microsoft.us` | `https://login.microsoftonline.us` |

## Logging

All operations are logged to the `Logs` directory with timestamps. Log files include:
- Connection status
- Import operations
- Success/failure status
- Error messages and stack traces

Log file format: `IntuneHydration_YYYYMMDD_HHMMSS.log`

## Troubleshooting

### Authentication Issues
- Ensure you have the required permissions in the target tenant
- For GCC High/DoD: Verify you're connecting from an authorized network
- Check that your account has the necessary security clearances

### Import Failures
- Review the log file for detailed error messages
- Verify configuration JSON files are valid
- Ensure you have the required Microsoft Graph permissions

### Network Issues
- Confirm network connectivity to the appropriate Microsoft Graph endpoint
- Check firewall rules and proxy settings
- For government clouds, verify VPN/network authorization

## Security Considerations

- **Never commit credentials** to source control
- Store configuration files securely, especially for government tenants
- Review all configurations before importing to production
- Use the `-WhatIf` parameter to preview changes
- Regularly audit imported configurations
- Follow your organization's security policies and procedures

## Contributing

Contributions are welcome! Please ensure:
- Code follows PowerShell best practices
- Documentation is updated
- Tenant-specific considerations are addressed
- Security implications are considered

## License

This project is provided as-is for use with Microsoft Intune environments.

## Support

For issues and questions:
- Open an issue on GitHub
- Review existing documentation in [EXAMPLES.md](EXAMPLES.md) and [QUICKSTART.md](QUICKSTART.md)
- Check Microsoft's official Intune documentation

## Additional Resources

- [Microsoft Intune Documentation](https://docs.microsoft.com/en-us/mem/intune/)
- [Microsoft Graph API Reference](https://docs.microsoft.com/en-us/graph/api/overview)
- [GCC High Technical Documentation](https://docs.microsoft.com/en-us/office365/servicedescriptions/office-365-platform-service-description/office-365-us-government/gcc-high-and-dod)
- [Azure Government Documentation](https://docs.microsoft.com/en-us/azure/azure-government/)
