# Intune Hydration Kit - Quick Start Guide

This guide will help you quickly get started with the Intune Hydration Kit for any tenant type.

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] PowerShell 5.1 or later installed
- [ ] Microsoft.Graph PowerShell SDK modules installed
- [ ] Your Azure AD Tenant ID
- [ ] Administrative credentials for Intune
- [ ] Appropriate network access for your tenant type
- [ ] Required security clearances (for government tenants)

## Step 1: Install Required Modules

```powershell
# Install Microsoft Graph PowerShell SDK
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Verify installation
Get-Module Microsoft.Graph -ListAvailable
```

## Step 2: Get Your Tenant ID

If you don't know your Tenant ID, you can find it in the Azure portal:

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Go to **Azure Active Directory**
3. Click **Properties**
4. Copy the **Tenant ID** (it's a GUID)

Alternatively, use PowerShell:
```powershell
Connect-AzureAD
(Get-AzureADTenantDetail).ObjectId
```

## Step 3: Download the Hydration Kit

```powershell
# Clone the repository
git clone https://github.com/jorgeasaurus/Intune-Hydration-Kit.git

# Navigate to the directory
cd Intune-Hydration-Kit
```

Or download as ZIP from GitHub and extract to your desired location.

## Step 4: Review Configuration Files (Optional)

Before importing, you may want to review the baseline configurations:

```powershell
# View available configurations
Get-ChildItem -Path .\Configurations -Recurse -Filter "*.json"

# Review a specific configuration
Get-Content .\Configurations\CompliancePolicies\Windows10-BaselineCompliance.json | ConvertFrom-Json
```

## Step 5: Run the Hydration Script

### For Commercial Tenants

```powershell
.\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "YOUR-TENANT-ID-HERE" -ImportAll
```

### For GCC Tenants

```powershell
.\Start-IntuneHydration.ps1 -TenantType GCC -TenantId "YOUR-TENANT-ID-HERE" -ImportAll
```

### For GCC High Tenants

**Important**: Ensure you're connected to an authorized government network.

```powershell
.\Start-IntuneHydration.ps1 -TenantType GCCHigh -TenantId "YOUR-TENANT-ID-HERE" -ImportAll
```

### For DoD Tenants

**Important**: Ensure you're connected to the DoD network infrastructure.

```powershell
.\Start-IntuneHydration.ps1 -TenantType DoD -TenantId "YOUR-TENANT-ID-HERE" -ImportAll
```

## Step 6: Authenticate

When prompted:

1. A browser window will open for authentication
2. Sign in with your Intune administrator credentials
3. Consent to the requested permissions if this is your first time
4. Return to the PowerShell window

**Note**: For GCC High and DoD tenants, ensure you use your government email address (e.g., user@agency.gov or user@mail.mil).

## Step 7: Monitor Progress

The script will:
1. Validate tenant access
2. Display security and compliance notices
3. Import configurations
4. Show progress for each configuration type
5. Display a summary of results

Watch for:
- **Green messages**: Successful imports
- **Yellow messages**: Warnings or skipped items
- **Red messages**: Errors that need attention

## Step 8: Review Results

After completion:

```powershell
# View the log file
$LogFile = Get-ChildItem -Path .\Logs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
notepad $LogFile.FullName
```

## Step 9: Verify in Intune Portal

1. Navigate to [Microsoft Endpoint Manager admin center](https://endpoint.microsoft.com)
   - GCC High: [https://endpoint.microsoft.us](https://endpoint.microsoft.us)
   - DoD: [https://endpoint.microsoft.us](https://endpoint.microsoft.us)

2. Check imported items:
   - **Devices > Compliance policies** - Review compliance policies
   - **Devices > Configuration profiles** - Review configuration profiles
   - **Groups > All groups** - Review dynamic groups

## Testing with WhatIf

To preview what would be imported without making actual changes:

```powershell
.\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "YOUR-TENANT-ID-HERE" -WhatIf
```

This is useful for:
- Understanding what will be imported
- Testing the script in production environments
- Creating documentation of changes

## Customizing Configurations

### Using Custom Configuration Path

```powershell
.\Start-IntuneHydration.ps1 -TenantType Commercial `
                            -TenantId "YOUR-TENANT-ID-HERE" `
                            -ConfigurationPath "C:\MyConfigs" `
                            -ImportAll
```

### Creating Tenant-Specific Configurations

Create subfolders for tenant-specific configs:

```powershell
# Create tenant-specific folder
New-Item -Path ".\Configurations\CompliancePolicies\GCCHigh" -ItemType Directory

# Copy and modify configuration
Copy-Item ".\Configurations\CompliancePolicies\Windows10-BaselineCompliance.json" `
          ".\Configurations\CompliancePolicies\GCCHigh\Windows10-GCCHighCompliance.json"

# Edit the configuration for GCC High requirements
notepad ".\Configurations\CompliancePolicies\GCCHigh\Windows10-GCCHighCompliance.json"
```

## Troubleshooting Quick Fixes

### Module Not Found
```powershell
# Reinstall Microsoft.Graph modules
Install-Module Microsoft.Graph -Force -AllowClobber
```

### Authentication Fails
```powershell
# Clear cached credentials
Disconnect-MgGraph
Clear-AzureRmContext -Force

# Try authenticating manually first
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"
```

### Network Connectivity Issues (Government Tenants)
- Verify VPN connection to government network
- Check proxy settings
- Confirm firewall rules allow access to government endpoints

### Permission Denied Errors
- Ensure you have Intune Administrator role
- Check that required Graph API permissions are granted
- Verify your account is active in the target tenant

## Next Steps

After successful hydration:

1. **Review and customize** imported configurations
2. **Assign configurations** to appropriate groups
3. **Test on pilot devices** before full deployment
4. **Monitor compliance** in the Intune portal
5. **Document any customizations** for your organization

## Getting Help

- Review detailed examples: [EXAMPLES.md](EXAMPLES.md)
- Check full documentation: [README.md](README.md)
- Open an issue on GitHub for bugs or questions
- Consult Microsoft Intune documentation for policy details

## Best Practices

✅ **Do:**
- Always use `-WhatIf` first in production environments
- Review logs after each run
- Test configurations on pilot devices
- Keep backups of existing configurations
- Document any customizations

❌ **Don't:**
- Run in production without testing
- Ignore warning messages
- Skip security notices for government tenants
- Share credentials or tenant IDs publicly
- Modify baseline files directly (copy them first)

## Quick Reference Card

| Tenant Type | Required Access | Network Requirements |
|-------------|----------------|---------------------|
| Commercial | Standard M365 Admin | Any network |
| GCC | FedRAMP Moderate | Govt network recommended |
| GCC High | FedRAMP High, US Person | US Govt network required |
| DoD | DoD IL5, Security Clearance | DoD network required |

## Support

For additional assistance:
- Microsoft Intune Support: [https://aka.ms/intunesupport](https://aka.ms/intunesupport)
- Azure Government Support: [https://aka.ms/azuregovsupport](https://aka.ms/azuregovsupport)
- GitHub Issues: [Repository Issues](https://github.com/jorgeasaurus/Intune-Hydration-Kit/issues)
