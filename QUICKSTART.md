# Quick Start Guide - Intune Hydration Kit

## 🚀 Quick Start (5 Minutes)

### Prerequisites Check
```powershell
# Check PowerShell version (need 5.1+)
$PSVersionTable.PSVersion

# Check if git is installed
git --version
```

### Basic Usage
```powershell
# 1. Clone the repository
git clone https://github.com/jorgeasaurus/Intune-Hydration-Kit.git
cd Intune-Hydration-Kit

# 2. Run the full hydration
.\Invoke-IntuneHydration.ps1

# 3. Authenticate when prompted (need Intune Administrator role)

# 4. Review the log file
Get-Content .\Logs\IntuneHydration_*.log -Tail 50
```

## 📋 Common Commands

### Full Hydration
```powershell
.\Invoke-IntuneHydration.ps1
```

### Groups Only
```powershell
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipEnrollment -SkipConditionalAccess
```

### Skip Conditional Access
```powershell
.\Invoke-IntuneHydration.ps1 -SkipConditionalAccess
```

### Specify Tenant
```powershell
.\Invoke-IntuneHydration.ps1 -TenantId "your-tenant-id"
```

## ⚙️ Parameters Quick Reference

| Parameter | Effect |
|-----------|--------|
| `-SkipPolicies` | Skip OpenIntuneBaseline import |
| `-SkipCompliance` | Skip compliance baselines |
| `-SkipSecurityBaselines` | Skip security baselines |
| `-SkipEnrollment` | Skip Autopilot & ESP |
| `-SkipGroups` | Skip dynamic groups |
| `-SkipConditionalAccess` | Skip CA policies |
| `-TenantId <id>` | Specify tenant ID |

## 🔑 Required Permissions

Your account needs these Microsoft Graph permissions:
- ✅ DeviceManagementConfiguration.ReadWrite.All
- ✅ DeviceManagementManagedDevices.ReadWrite.All
- ✅ DeviceManagementServiceConfig.ReadWrite.All
- ✅ Group.ReadWrite.All
- ✅ Policy.ReadWrite.ConditionalAccess
- ✅ Directory.Read.All

**Role Required**: Intune Administrator or Global Administrator

## 📊 What Gets Created

### Dynamic Groups (16)
- **OS**: Windows, iOS, Android, macOS
- **Manufacturers**: Microsoft, Dell, HP, Lenovo
- **Autopilot**: Autopilot devices, Non-Autopilot devices
- **Compliance**: Compliant, Non-compliant
- **Models**: Surface Laptop, Surface Pro

### Compliance Policies (4)
- Windows Compliance Baseline
- iOS Compliance Baseline
- Android Compliance Baseline
- macOS Compliance Baseline

### Enrollment Profiles (2)
- Corporate Autopilot Profile
- Corporate ESP Profile

### Conditional Access Policies (10)
All created **disabled** - review and enable manually:
1. MFA for Administrators
2. Block Legacy Authentication
3. MFA for Azure Management
4. Require Compliant Device
5. Block Unknown Locations
6. App Protection for Mobile
7. MFA for All Users
8. Block Risky Sign-ins
9. Require Terms of Use
10. Password Change for Risky Users

## ⚠️ Important Notes

### Before Running
1. ✅ Test in non-production tenant first
2. ✅ Have Intune Administrator permissions
3. ✅ Internet connectivity required
4. ✅ Git must be installed

### After Running
1. 🔍 Review the log file
2. 🔍 Check created groups in Azure AD
3. 🔍 Review compliance policies
4. ⚠️ **Enable CA policies one at a time**
5. 🧪 Test with pilot devices first

### Safety Features
- ✅ All CA policies disabled by default
- ✅ No data deletion operations
- ✅ No hardcoded credentials
- ✅ Comprehensive logging
- ✅ Cleanup of temporary files

## 🛠️ Troubleshooting

### Authentication Failed
```powershell
# Manually authenticate first
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","Group.ReadWrite.All"

# Then run the script
.\Invoke-IntuneHydration.ps1
```

### Module Not Found
```powershell
# Install modules manually
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
```

### Git Not Found
```powershell
# Windows: Install Git from https://git-scm.com/download/win
# macOS: brew install git
# Linux: sudo apt-get install git
```

### Review Logs
```powershell
# View latest log
Get-ChildItem .\Logs\ | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content

# View errors only
Get-Content .\Logs\IntuneHydration_*.log | Select-String "ERROR"

# View warnings
Get-Content .\Logs\IntuneHydration_*.log | Select-String "WARNING"
```

## 📚 More Information

- **Full Documentation**: See [README.md](README.md)
- **Usage Examples**: See [EXAMPLES.md](EXAMPLES.md)
- **Implementation Details**: See [IMPLEMENTATION.md](IMPLEMENTATION.md)

## 🔄 Update the Script

```powershell
# Pull latest changes
git pull origin main

# Run updated version
.\Invoke-IntuneHydration.ps1
```

## 💡 Pro Tips

1. **Start Small**: Use skip parameters to test components individually
2. **Review First**: Check Config.json before running
3. **Log Everything**: Always keep logs for audit purposes
4. **Test Thoroughly**: Never enable CA policies without testing
5. **Document Changes**: Keep track of customizations
6. **Backup First**: Export existing policies before running
7. **Pilot Devices**: Test with small group first

## 🎯 Common Scenarios

### New Tenant Setup
```powershell
# Full hydration for brand new tenant
.\Invoke-IntuneHydration.ps1
```

### Existing Tenant - Add Groups Only
```powershell
# Add dynamic groups to existing tenant
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipEnrollment -SkipConditionalAccess
```

### Compliance Refresh
```powershell
# Update compliance policies only
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipSecurityBaselines -SkipEnrollment -SkipGroups -SkipConditionalAccess
```

## 📞 Getting Help

1. Check the log file in `Logs\` directory
2. Review [README.md](README.md) troubleshooting section
3. Review [EXAMPLES.md](EXAMPLES.md) for scenarios
4. Open an issue on GitHub (remove sensitive data from logs)

## ✅ Post-Hydration Checklist

- [ ] Review log file for errors/warnings
- [ ] Verify dynamic groups created in Azure AD
- [ ] Check compliance policies in Intune portal
- [ ] Review Autopilot profile settings
- [ ] Review ESP profile settings
- [ ] Check CA policies (all should be disabled)
- [ ] Test with pilot devices
- [ ] Enable CA policies one at a time
- [ ] Document any customizations made
- [ ] Schedule regular reviews

---

**Remember**: This is a framework that provides templates and structure. Review all configurations before deploying to production!

**Version**: 1.0.0  
**Last Updated**: 2025
