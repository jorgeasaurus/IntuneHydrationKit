# Intune-Hydration-Kit — MVP Overview

This document defines the **minimum set of functional components** required for the MVP of the Intune-Hydration-Kit.  
Everything here is implemented **purely in PowerShell** using Microsoft Graph API calls and the IntuneManagement module.  
No “agents,” no abstractions — just straightforward execution steps.

The MVP hydrates a new Intune tenant with:

- All policies from **OpenIntuneBaseline**
- A **Compliance Baseline Pack**
- **Enrollment Profiles**
- A **Complete Dynamic Group Suite**
- **Microsoft Security Baselines**
- A **Conditional Access Starter Pack** (all **disabled** by default)


Nothing more.

---

# 1. Authentication

PowerShell scripts will:
- Accept credentials or certificate-based auth  
- Connect to Microsoft Graph with required scopes  
- Validate Intune license availability  
- Confirm MDM authority is set  

```ps1
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","Group.ReadWrite.All","Policy.ReadWrite.ConditionalAccess","Directory.ReadWrite.All"
```

---

# 2. Import OpenIntuneBaseline Policies

### Tasks:
- Clone from `Micke-K/IntuneManagement`
- Clone or download policies from `SkipToTheEndpoint/OpenIntuneBaseline`
- Loop through JSON files
- Use IntuneManagement module
- Create or update profiles as needed

### Output:
- Policy names  
- IDs created  
- Errors/warnings  

---

# 3. Import Compliance Baseline Pack

### Tasks:
- Read prepackaged compliance policy templates (`./Baselines/Compliance/`)
- Import using `New-MgDeviceManagementCompliancePolicy` or IntuneManagement functions
- Assign to platform-specific dynamic groups

### Output:
- Compliance policies created  
- Assignment groups applied  

---

# 4. Apply Enrollment Profiles

### Windows Autopilot:
- Create/ensure:
  - Autopilot deployment profile
  - ESP profile
  - Device naming template (optional)

### macOS / iOS (Optional based on ABM availability):
- Create MDM enrollment profiles  
- Assign to macOS or iOS device groups  

### Output:
- Profile IDs  
- Assignment targets  

---

# 5. Create Dynamic Group Suite

All dynamic groups are created using `New-MgGroup` with `-GroupTypes DynamicMembership` and OData membership rules.

### **Minimum Required Dynamic Groups**

#### OS Groups
- Windows 10
- Windows 11
- macOS
- iOS/iPadOS
- Android

#### Manufacturer Groups
- Dell  
- HP  
- Lenovo  
- Microsoft  
- Apple  

#### Model Groups  
(Parameterized, only if your tenant contains sample devices)

#### Autopilot Groups
- Autopilot Devices  
- Non-Autopilot Devices  

#### Compliance State Groups
- Compliant  
- NonCompliant  
- Unknown  

### Output:
- Group names + IDs  
- Rules used  
- Errors creating invalid rules  

---

# 6. Import Microsoft Security Baselines

Using PowerShell:
- Load security baseline JSON templates
- Create/update security baseline objects
- Assign to OS-specific dynamic groups

Supported baselines:
- Windows 10/11  
- Microsoft Edge  
- M365 Apps  

### Output:
- Baseline objects created  
- Assignment groups  

---

# 7. Import Conditional Access Starter Pack (Disabled)

All policies are imported with:

```json
"state": "disabled"
```

Required starter pack includes:
- Require MFA  
- Require compliant device  
- Block legacy authentication  
- Admin protection  
- Break-glass bypass policy  

### Tasks:
- Read CA templates from `./ConditionalAccess/`
- Use `New-MgIdentityConditionalAccessPolicy`
- Force `"state": "disabled"` regardless of template input

### Output:
- CA policies created  
- Confirmed disabled status  

---

# 8. Summary Output

At the end of execution, the script writes a single file:

```
./Reports/Hydration-Summary.md
```

This includes:
- Number of baseline policies imported  
- Compliance profiles created  
- Enrollment profiles created  
- Dynamic groups created  
- Security baselines imported  
- CA policies created (all disabled)  
- Errors / warnings / skipped items  

---

# 9. Explicit Non-Goals for MVP

These items are **not included**:

- Apps or Win32 deployments  
- RBAC roles / scope tags  
- Autopilot device imports  
- Branding  
- Drift detection  
- GitOps or GitHub Actions flows  
- Reporting dashboards  
- Terraform integration  
- SCCM or FleetDM connectors  

The MVP exists *only* to bootstrap an Intune tenant with best-practice defaults.

---

# End of Document
