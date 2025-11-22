# Intune Hydration Kit - Usage Examples

This document provides detailed examples for using the Intune Hydration Kit across different tenant types and scenarios.

## Table of Contents

1. [Commercial Tenant Examples](#commercial-tenant-examples)
2. [GCC Tenant Examples](#gcc-tenant-examples)
3. [GCC High Tenant Examples](#gcc-high-tenant-examples)
4. [DoD Tenant Examples](#dod-tenant-examples)
5. [Advanced Scenarios](#advanced-scenarios)
6. [Custom Configuration Examples](#custom-configuration-examples)

---

## Commercial Tenant Examples

### Example 1: Basic Hydration for Commercial Tenant

**Scenario**: First-time setup of a new commercial tenant with baseline policies.

```powershell
# Basic import with all configurations
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d" `
    -ImportAll

# Expected Output:
# [2025-11-22 10:00:00] [Info] Starting Intune Hydration for Commercial tenant
# [2025-11-22 10:00:01] [Info] Connecting to Microsoft Graph API...
# [2025-11-22 10:00:05] [Success] Successfully connected to Microsoft Graph
# [2025-11-22 10:00:06] [Success] Tenant validation successful
# [2025-11-22 10:00:07] [Info] Found 5 configuration type(s)
# ...
```

### Example 2: Preview Changes with WhatIf

**Scenario**: Review what configurations would be imported before making actual changes.

```powershell
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d" `
    -WhatIf

# Expected Output:
# [2025-11-22 10:00:00] [Info] Starting Intune Hydration for Commercial tenant
# ...
# [2025-11-22 10:00:10] [Info] [WhatIf] Would import: Windows10-BaselineCompliance.json
# [2025-11-22 10:00:10] [Info] [WhatIf] Would import: iOS-BaselineCompliance.json
```

### Example 3: Custom Configuration Path

**Scenario**: Use custom configuration files stored in a different location.

```powershell
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d" `
    -ConfigurationPath "C:\IntuneConfigs\Production" `
    -ImportAll
```

---

## GCC Tenant Examples

### Example 4: GCC Tenant Initial Setup

**Scenario**: Setting up a new GCC tenant for a federal agency.

```powershell
# GCC tenants use the same Graph endpoint as Commercial
# but require FedRAMP Moderate authorization
.\Start-IntuneHydration.ps1 `
    -TenantType GCC `
    -TenantId "f1e2d3c4-b5a6-4958-8877-665544332211" `
    -ImportAll

# Expected Output includes compliance notice:
# [2025-11-22 10:00:00] [Warning] === Security and Compliance Notice ===
# [2025-11-22 10:00:00] [Warning] GCC Environment: Ensure you have FedRAMP Moderate authorization.
# [2025-11-22 10:00:00] [Warning] Network: Access from approved government networks required.
```

### Example 5: GCC with Custom Compliance Requirements

**Scenario**: Import configurations with agency-specific compliance policies.

```powershell
# First, create agency-specific configurations
New-Item -Path ".\Configurations\CompliancePolicies\GCC" -ItemType Directory -Force

# Copy and customize the baseline
Copy-Item ".\Configurations\CompliancePolicies\Windows10-BaselineCompliance.json" `
          ".\Configurations\CompliancePolicies\GCC\Windows10-AgencyCompliance.json"

# Edit to add agency-specific requirements
# (e.g., require specific OS versions, additional security settings)

# Import configurations
.\Start-IntuneHydration.ps1 `
    -TenantType GCC `
    -TenantId "f1e2d3c4-b5a6-4958-8877-665544332211" `
    -ImportAll
```

---

## GCC High Tenant Examples

### Example 6: GCC High Tenant Setup

**Scenario**: Initial configuration of a GCC High tenant for a defense contractor.

**Prerequisites**:
- US Person status verified
- Connected to authorized government network
- FedRAMP High authorization in place

```powershell
.\Start-IntuneHydration.ps1 `
    -TenantType GCCHigh `
    -TenantId "a1a2a3a4-b1b2-c1c2-d1d2-e1e2e3e4e5e6" `
    -ImportAll

# Expected Output:
# [2025-11-22 10:00:00] [Info] Starting Intune Hydration for GCCHigh tenant
# [2025-11-22 10:00:01] [Info] Microsoft Graph Endpoint: https://graph.microsoft.us
# [2025-11-22 10:00:01] [Info] Azure AD Login Endpoint: https://login.microsoftonline.us
# [2025-11-22 10:00:02] [Warning] === Security and Compliance Notice ===
# [2025-11-22 10:00:02] [Warning] GCC High Environment: Requires FedRAMP High authorization and US Person status.
# [2025-11-22 10:00:02] [Warning] Network: Must connect from US Government network or approved VPN.
# [2025-11-22 10:00:02] [Warning] Data Classification: Suitable for CUI and ITAR controlled data.
```

### Example 7: GCC High with ITAR Compliance Configurations

**Scenario**: Configure Intune for ITAR-compliant environment.

```powershell
# Create GCC High specific folder
New-Item -Path ".\Configurations\CompliancePolicies\GCCHigh" -ItemType Directory -Force

# Create ITAR-specific compliance policy
$ITARCompliance = @{
    "@odata.type" = "#microsoft.graph.windows10CompliancePolicy"
    "displayName" = "Windows 10 - ITAR Compliance Policy"
    "description" = "Enhanced compliance requirements for ITAR controlled data"
    "passwordRequired" = $true
    "passwordMinimumLength" = 14
    "passwordRequiredType" = "alphanumeric"
    "passwordMinutesOfInactivityBeforeLock" = 10
    "passwordExpirationDays" = 60
    "passwordPreviousPasswordBlockCount" = 24
    "requireHealthyDeviceReport" = $true
    "osMinimumVersion" = "10.0.19044"
    "bitLockerEnabled" = $true
    "secureBootEnabled" = $true
    "codeIntegrityEnabled" = $true
    "storageRequireEncryption" = $true
    "tpmRequired" = $true
} | ConvertTo-Json -Depth 10

$ITARCompliance | Out-File ".\Configurations\CompliancePolicies\GCCHigh\Windows10-ITARCompliance.json"

# Import configurations
.\Start-IntuneHydration.ps1 `
    -TenantType GCCHigh `
    -TenantId "a1a2a3a4-b1b2-c1c2-d1d2-e1e2e3e4e5e6" `
    -ImportAll
```

### Example 8: GCC High Preview Before Import

**Scenario**: Validate configurations before importing to production GCC High environment.

```powershell
# Always test with WhatIf in government environments first
.\Start-IntuneHydration.ps1 `
    -TenantType GCCHigh `
    -TenantId "a1a2a3a4-b1b2-c1c2-d1d2-e1e2e3e4e5e6" `
    -WhatIf

# Review the output, then run actual import
.\Start-IntuneHydration.ps1 `
    -TenantType GCCHigh `
    -TenantId "a1a2a3a4-b1b2-c1c2-d1d2-e1e2e3e4e5e6" `
    -ImportAll
```

---

## DoD Tenant Examples

### Example 9: DoD Tenant Initial Configuration

**Scenario**: Configure Intune for DoD environment with IL5 classification.

**Prerequisites**:
- Active DoD security clearance
- Connected to DoD network (SIPRNET or approved connection)
- DoD IL5 authorization

```powershell
.\Start-IntuneHydration.ps1 `
    -TenantType DoD `
    -TenantId "d0d1d2d3-d4d5-d6d7-d8d9-d0d1d2d3d4d5" `
    -ImportAll

# Expected Output:
# [2025-11-22 10:00:00] [Info] Starting Intune Hydration for DoD tenant
# [2025-11-22 10:00:01] [Info] Microsoft Graph Endpoint: https://dod-graph.microsoft.us
# [2025-11-22 10:00:01] [Info] Azure AD Login Endpoint: https://login.microsoftonline.us
# [2025-11-22 10:00:02] [Warning] === Security and Compliance Notice ===
# [2025-11-22 10:00:02] [Warning] DoD Environment: Requires DoD IL5 authorization and security clearance.
# [2025-11-22 10:00:02] [Warning] Network: Must connect from DoD network infrastructure.
# [2025-11-22 10:00:02] [Warning] Data Classification: Suitable for classified data up to IL5.
```

### Example 10: DoD with Enhanced Security Configurations

**Scenario**: Deploy maximum security configurations for classified DoD environment.

```powershell
# Create DoD-specific configuration folder
New-Item -Path ".\Configurations\CompliancePolicies\DoD" -ItemType Directory -Force
New-Item -Path ".\Configurations\SecurityBaselines\DoD" -ItemType Directory -Force

# Create DoD-specific compliance policy
$DoDCompliance = @{
    "@odata.type" = "#microsoft.graph.windows10CompliancePolicy"
    "displayName" = "Windows 10 - DoD IL5 Compliance Policy"
    "description" = "Maximum security compliance for DoD IL5 classification"
    "passwordRequired" = $true
    "passwordMinimumLength" = 15
    "passwordRequiredType" = "alphanumeric"
    "passwordMinutesOfInactivityBeforeLock" = 5
    "passwordExpirationDays" = 60
    "passwordPreviousPasswordBlockCount" = 24
    "requireHealthyDeviceReport" = $true
    "osMinimumVersion" = "10.0.19044"
    "earlyLaunchAntiMalwareDriverEnabled" = $true
    "bitLockerEnabled" = $true
    "secureBootEnabled" = $true
    "codeIntegrityEnabled" = $true
    "storageRequireEncryption" = $true
    "tpmRequired" = $true
    "defenderEnabled" = $true
    "rtpEnabled" = $true
    "antivirusRequired" = $true
    "antiSpywareRequired" = $true
} | ConvertTo-Json -Depth 10

$DoDCompliance | Out-File ".\Configurations\CompliancePolicies\DoD\Windows10-DoDCompliance.json"

# Import with DoD-specific configurations
.\Start-IntuneHydration.ps1 `
    -TenantType DoD `
    -TenantId "d0d1d2d3-d4d5-d6d7-d8d9-d0d1d2d3d4d5" `
    -ImportAll
```

---

## Advanced Scenarios

### Example 11: Multi-Tenant Management Script

**Scenario**: Manage multiple tenants with a single script.

```powershell
# Define tenant configurations
$Tenants = @(
    @{
        Name = "Commercial Production"
        Type = "Commercial"
        TenantId = "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d"
    },
    @{
        Name = "GCC Development"
        Type = "GCC"
        TenantId = "f1e2d3c4-b5a6-4958-8877-665544332211"
    }
)

# Process each tenant
foreach ($Tenant in $Tenants) {
    Write-Host "`n=== Processing $($Tenant.Name) ===" -ForegroundColor Cyan
    
    .\Start-IntuneHydration.ps1 `
        -TenantType $Tenant.Type `
        -TenantId $Tenant.TenantId `
        -ImportAll
    
    Write-Host "=== Completed $($Tenant.Name) ===`n" -ForegroundColor Green
}
```

### Example 12: Selective Configuration Import

**Scenario**: Import only specific configuration types.

```powershell
# Import only compliance policies and dynamic groups
$ConfigPath = ".\Configurations"

# Temporarily move other config folders
$TempPath = "C:\Temp\IntuneBackup"
New-Item -Path $TempPath -ItemType Directory -Force

Move-Item "$ConfigPath\ConfigurationProfiles" "$TempPath\ConfigurationProfiles" -Force
Move-Item "$ConfigPath\SecurityBaselines" "$TempPath\SecurityBaselines" -Force

# Run import
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d" `
    -ImportAll

# Restore folders
Move-Item "$TempPath\ConfigurationProfiles" "$ConfigPath\ConfigurationProfiles" -Force
Move-Item "$TempPath\SecurityBaselines" "$ConfigPath\SecurityBaselines" -Force
```

### Example 13: Automated Scheduled Hydration

**Scenario**: Schedule regular configuration updates using Windows Task Scheduler.

```powershell
# Create scheduled task script
$ScheduledScript = @'
# Scheduled Intune Hydration
$ErrorActionPreference = "Stop"

try {
    Set-Location "C:\IntuneHydration"
    
    .\Start-IntuneHydration.ps1 `
        -TenantType GCC `
        -TenantId "f1e2d3c4-b5a6-4958-8877-665544332211" `
        -ImportAll
    
    # Send success notification
    Send-MailMessage -To "admin@agency.gov" `
                     -From "intune@agency.gov" `
                     -Subject "Intune Hydration Completed Successfully" `
                     -Body "Configuration update completed at $(Get-Date)" `
                     -SmtpServer "smtp.agency.gov"
}
catch {
    # Send failure notification
    Send-MailMessage -To "admin@agency.gov" `
                     -From "intune@agency.gov" `
                     -Subject "Intune Hydration Failed" `
                     -Body "Error: $($_.Exception.Message)" `
                     -SmtpServer "smtp.agency.gov"
}
'@

$ScheduledScript | Out-File "C:\IntuneHydration\ScheduledHydration.ps1"

# Create scheduled task (run as appropriate service account)
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
                                   -Argument "-File C:\IntuneHydration\ScheduledHydration.ps1"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 2am
Register-ScheduledTask -TaskName "IntuneHydration" `
                       -Action $Action `
                       -Trigger $Trigger `
                       -Description "Weekly Intune configuration update"
```

---

## Custom Configuration Examples

### Example 14: Creating Custom Compliance Policy

**Scenario**: Create a custom compliance policy for specific business requirements.

```powershell
# Define custom compliance policy
$CustomCompliance = @{
    "@odata.type" = "#microsoft.graph.windows10CompliancePolicy"
    "displayName" = "Windows 10 - Financial Services Compliance"
    "description" = "Compliance policy for financial services industry"
    "passwordRequired" = $true
    "passwordMinimumLength" = 12
    "passwordRequiredType" = "alphanumeric"
    "passwordMinutesOfInactivityBeforeLock" = 10
    "passwordExpirationDays" = 90
    "passwordPreviousPasswordBlockCount" = 12
    "requireHealthyDeviceReport" = $true
    "osMinimumVersion" = "10.0.19041"
    "bitLockerEnabled" = $true
    "secureBootEnabled" = $true
    "codeIntegrityEnabled" = $true
    "storageRequireEncryption" = $true
    "activeFirewallRequired" = $true
    "defenderEnabled" = $true
    "rtpEnabled" = $true
    "antivirusRequired" = $true
    "scheduledActionsForRule" = @(
        @{
            "ruleName" = "PasswordRequired"
            "scheduledActionConfigurations" = @(
                @{
                    "@odata.type" = "#microsoft.graph.deviceComplianceScheduledActionForRule"
                    "actionType" = "block"
                    "gracePeriodHours" = 0
                    "notificationTemplateId" = ""
                }
            )
        }
    )
}

# Save to file
$CustomCompliance | ConvertTo-Json -Depth 10 | 
    Out-File ".\Configurations\CompliancePolicies\Windows10-FinancialServices.json"

# Import
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d" `
    -ImportAll
```

### Example 15: Dynamic Group for Pilot Users

**Scenario**: Create dynamic groups for pilot testing in different environments.

```powershell
# Create pilot user group configuration
$PilotGroup = @{
    "displayName" = "Intune Pilot Users"
    "description" = "Dynamic group for Intune configuration pilot testing"
    "mailNickname" = "IntunePilotUsers"
    "membershipRule" = '(user.department -eq "IT") and (user.extensionAttribute1 -eq "Pilot")'
    "membershipRuleProcessingState" = "On"
}

$PilotGroup | ConvertTo-Json | 
    Out-File ".\Configurations\DynamicGroups\PilotUsers.json"

# Create pilot device group
$PilotDevices = @{
    "displayName" = "Intune Pilot Devices"
    "description" = "Dynamic group for pilot testing devices"
    "mailNickname" = "IntunePilotDevices"
    "membershipRule" = '(device.deviceOwnership -eq "Company") and (device.enrollmentProfileName -eq "Pilot")'
    "membershipRuleProcessingState" = "On"
}

$PilotDevices | ConvertTo-Json | 
    Out-File ".\Configurations\DynamicGroups\PilotDevices.json"

# Import pilot groups
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d" `
    -ImportAll
```

---

## Tips and Best Practices

### Testing Strategy

1. **Always use WhatIf first** in production environments
2. **Test in dev/test tenant** before production
3. **Use pilot groups** for gradual rollout
4. **Monitor logs** for any errors or warnings
5. **Validate configurations** in the Intune portal after import

### Configuration Management

- Keep tenant-specific configurations in separate folders
- Use version control (Git) for configuration files
- Document all customizations
- Regularly review and update baseline configurations
- Test configuration changes in non-production environments first

### Security Considerations

- Never commit credentials to version control
- Use Azure Key Vault for sensitive data
- Follow least privilege principle for service accounts
- Audit configuration changes regularly
- Keep detailed logs of all imports

### Government Tenant Specific

- Always verify network connectivity before starting
- Confirm security clearances are current
- Document compliance requirements
- Test in lower classification environments when possible
- Follow agency-specific security policies

---

## Troubleshooting Examples

### Example 16: Handling Authentication Failures

```powershell
# If authentication fails, manually connect first
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All", `
                        "DeviceManagementManagedDevices.ReadWrite.All", `
                        "Group.ReadWrite.All" `
                -TenantId "your-tenant-id"

# Verify connection
Get-MgContext

# Then run hydration script (it will use existing connection)
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "your-tenant-id" `
    -ImportAll
```

### Example 17: Recovering from Failed Import

```powershell
# Check the log file for details
$LatestLog = Get-ChildItem ".\Logs" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $LatestLog.FullName | Select-String "Error" -Context 2,2

# Remove failed configuration file temporarily if needed
Move-Item ".\Configurations\CompliancePolicies\FailedConfig.json" ".\Backup\" -Force

# Re-run import
.\Start-IntuneHydration.ps1 `
    -TenantType Commercial `
    -TenantId "your-tenant-id" `
    -ImportAll

# Restore and fix the configuration
Move-Item ".\Backup\FailedConfig.json" ".\Configurations\CompliancePolicies\" -Force
```

---

## Additional Resources

- **Microsoft Graph API Explorer**: https://developer.microsoft.com/graph/graph-explorer
- **Intune Configuration Examples**: https://github.com/microsoftgraph/powershell-intune-samples
- **Government Cloud Documentation**: https://docs.microsoft.com/en-us/office365/servicedescriptions/office-365-platform-service-description/office-365-us-government/gcc-high-and-dod

## Getting Help

If you encounter issues:

1. Check the log files in the `Logs` directory
2. Review the [QUICKSTART.md](QUICKSTART.md) guide
3. Consult the [README.md](README.md) documentation
4. Open an issue on GitHub with log files and error messages
5. Contact Microsoft support for tenant-specific issues
