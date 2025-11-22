# Intune Hydration Kit - Usage Examples

This document provides practical examples for using the Intune Hydration Kit in different scenarios.

## Scenario 1: Complete Tenant Hydration (New Tenant)

For a brand new Intune tenant, run the full hydration process:

```powershell
.\Invoke-IntuneHydration.ps1
```

**What happens:**
- Imports all OpenIntuneBaseline policies
- Creates compliance baselines for all platforms
- Imports Microsoft Security Baselines
- Creates Autopilot and ESP enrollment profiles
- Creates 16 dynamic groups
- Imports 10 Conditional Access policies (disabled)

**Time estimate:** 10-15 minutes

## Scenario 2: Only Enrollment and Groups

If you already have policies but need enrollment profiles and groups:

```powershell
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipConditionalAccess
```

**What happens:**
- Creates Autopilot profile with OOBE customization
- Creates ESP profile with installation tracking
- Creates all dynamic groups

**Time estimate:** 2-3 minutes

## Scenario 3: Only Conditional Access Policies

To import only the Conditional Access starter pack:

```powershell
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipEnrollment -SkipGroups
```

**What happens:**
- Imports 10 CA policies, all disabled
- You can then review and enable them one by one

**Time estimate:** 1-2 minutes

## Scenario 4: Compliance and Security Only

For organizations that already have groups and enrollment configured:

```powershell
.\Invoke-IntuneHydration.ps1 -SkipEnrollment -SkipGroups -SkipConditionalAccess
```

**What happens:**
- Imports all OpenIntuneBaseline policies
- Creates compliance baselines
- Imports Microsoft Security Baselines

**Time estimate:** 8-10 minutes

## Scenario 5: Specific Tenant with Pre-authentication

If you need to specify a tenant and want to prepare authentication:

```powershell
# First, authenticate manually
Connect-MgGraph -TenantId "your-tenant-id-here" -Scopes @(
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementManagedDevices.ReadWrite.All",
    "DeviceManagementServiceConfig.ReadWrite.All",
    "Group.ReadWrite.All",
    "Policy.ReadWrite.ConditionalAccess",
    "Directory.Read.All"
)

# Then run the script
.\Invoke-IntuneHydration.ps1 -TenantId "your-tenant-id-here"
```

## Scenario 6: Incremental Hydration (Multi-day approach)

For large organizations that want to deploy gradually:

### Day 1: Groups and Compliance
```powershell
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipSecurityBaselines -SkipEnrollment -SkipConditionalAccess
```

### Day 2: Enrollment Profiles
```powershell
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipGroups -SkipConditionalAccess
```

### Day 3: Configuration Policies
```powershell
.\Invoke-IntuneHydration.ps1 -SkipCompliance -SkipSecurityBaselines -SkipEnrollment -SkipGroups -SkipConditionalAccess
```

### Day 4: Security Baselines
```powershell
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipEnrollment -SkipGroups -SkipConditionalAccess
```

### Day 5: Conditional Access (Review and Enable Manually)
```powershell
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipEnrollment -SkipGroups
```

## Scenario 7: Re-running After Customization

If you've customized `Config.json` with your organization's settings:

```powershell
# Edit Config.json with your settings
notepad Config.json

# Run the script - it will use your custom settings
.\Invoke-IntuneHydration.ps1
```

## Scenario 8: Testing in Lab Environment

For testing purposes in a lab tenant:

```powershell
# Test groups only first
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipEnrollment -SkipConditionalAccess

# Verify groups were created successfully in the portal
# Then run the full hydration
.\Invoke-IntuneHydration.ps1
```

## Scenario 9: Automated Execution with Logging

For automation or CI/CD pipelines:

```powershell
# Run with transcript logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Start-Transcript -Path ".\Transcript_$timestamp.log"

try {
    .\Invoke-IntuneHydration.ps1
}
finally {
    Stop-Transcript
}
```

## Scenario 10: Troubleshooting Mode

If you encounter issues, run with verbose output:

```powershell
# Enable verbose output
$VerbosePreference = "Continue"

# Run the script
.\Invoke-IntuneHydration.ps1 -Verbose

# Check the log file
Get-Content .\Logs\IntuneHydration_*.log | Select-Object -Last 50
```

## Post-Hydration Tasks

After running the hydration script, complete these manual tasks:

### 1. Review Dynamic Groups
```powershell
# Connect to Microsoft Graph
Connect-MgGraph

# List all dynamic groups
Get-MgGroup -Filter "groupTypes/any(c:c eq 'DynamicMembership')" | 
    Select-Object DisplayName, MembershipRule | 
    Format-Table -AutoSize
```

### 2. Test Compliance Policies
- Enroll a test device for each platform
- Verify compliance evaluation
- Adjust policies as needed

### 3. Enable Conditional Access Policies (Gradually)
- Start with CA001 (Require MFA for Administrators)
- Test thoroughly before enabling the next policy
- Use report-only mode if available

### 4. Test Autopilot Enrollment
- Register a test device in Autopilot
- Run through the OOBE experience
- Verify ESP behavior

### 5. Monitor and Adjust
- Review policy compliance reports
- Check device enrollment success rates
- Adjust dynamic group rules if needed
- Fine-tune Autopilot and ESP settings

## Common Customizations

### Custom Device Naming
Edit the Autopilot profile in the script or Config.json:
```json
"DeviceNameTemplate": "CORP-%SERIAL%"
```

Options:
- `%SERIAL%` - Device serial number
- `%RAND:5%` - 5 random characters
- `CORP-%SERIAL%` - Results in "CORP-123456789"

### Compliance Password Requirements
Edit compliance baselines in the script:
```powershell
passwordMinimumLength = 12  # Change to your requirement
```

### Dynamic Group Membership Rules
Common customizations:
```
# Only Windows 11 devices
(device.deviceOSType -eq "Windows") and (device.deviceOSVersion -startsWith "10.0.22")

# Only Autopilot devices from specific manufacturer
(device.devicePhysicalIds -any (_ -eq "[ZTDId]")) and (device.deviceManufacturer -eq "Dell Inc.")

# Compliant Windows devices only
(device.deviceOSType -eq "Windows") and (device.isCompliant -eq true)
```

## Tips for Success

1. **Always test in a lab tenant first**
2. **Review all logs after execution**
3. **Start with groups and compliance, then add policies**
4. **Don't enable CA policies until thoroughly tested**
5. **Document any customizations you make**
6. **Keep the script updated with your organization's changes**
7. **Run the script during maintenance windows for production tenants**
8. **Have a rollback plan for each policy type**

## Getting Help

If you encounter issues:

1. Check the log file in the `Logs` directory
2. Review the README.md troubleshooting section
3. Verify your permissions in Azure AD and Intune
4. Test individual components using the skip parameters
5. Open an issue on GitHub with log excerpts (remove sensitive data)
