# Security and Compliance Guide

This document outlines the security and compliance considerations for using the Intune Hydration Kit across different Microsoft 365 tenant types.

## Overview

Each tenant type has specific security requirements and compliance standards that must be met:

- **Commercial**: Standard Microsoft 365 security practices
- **GCC**: FedRAMP Moderate compliance
- **GCC High**: FedRAMP High compliance, suitable for CUI and ITAR
- **DoD**: DoD IL5 compliance, suitable for classified information

## Authentication and Authorization

### Required Permissions

The Intune Hydration Kit requires the following Microsoft Graph API permissions:

| Permission | Type | Purpose |
|------------|------|---------|
| `DeviceManagementConfiguration.ReadWrite.All` | Application/Delegated | Create and modify device configurations |
| `DeviceManagementManagedDevices.ReadWrite.All` | Application/Delegated | Manage enrolled devices |
| `DeviceManagementServiceConfig.ReadWrite.All` | Application/Delegated | Configure Intune service settings |
| `Group.ReadWrite.All` | Application/Delegated | Create and manage Azure AD groups |
| `Directory.Read.All` | Application/Delegated | Read directory data |

### Authentication Methods

#### Interactive Authentication (Recommended for Initial Setup)
```powershell
# User signs in through browser
.\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "your-tenant-id"
```

#### Service Principal Authentication (For Automation)
Not recommended for government tenants without proper security controls.

### Multi-Factor Authentication (MFA)

- **Commercial**: MFA recommended
- **GCC**: MFA required
- **GCC High**: MFA required
- **DoD**: MFA required with CAC/PIV card

## Tenant-Specific Security Requirements

### Commercial Tenants

**Compliance Level**: Standard Microsoft 365 Security

**Requirements**:
- Valid Microsoft 365 subscription
- Global Administrator or Intune Administrator role
- MFA recommended but not enforced

**Best Practices**:
- Enable MFA for all administrative accounts
- Use Conditional Access policies
- Enable audit logging
- Regular security reviews

**Network Requirements**:
- No specific network restrictions
- Standard internet connectivity

### GCC (Government Community Cloud) Tenants

**Compliance Level**: FedRAMP Moderate

**Requirements**:
- FedRAMP Moderate authorization
- US-based support personnel
- Government email domain (recommended)

**Security Controls**:
- MFA required for all administrative accounts
- Conditional Access policies enforced
- Enhanced audit logging
- Data residency in US datacenters

**Network Requirements**:
- Access from approved government networks recommended
- VPN to government network preferred
- Firewall rules must allow:
  - `https://graph.microsoft.com`
  - `https://login.microsoftonline.com`

**Data Classification**:
- Suitable for: Unclassified government data
- Not suitable for: CUI, classified information

### GCC High (Government Community Cloud High) Tenants

**Compliance Level**: FedRAMP High, DFARS, ITAR

**Requirements**:
- FedRAMP High authorization
- **US Person status required** (US Citizen or Permanent Resident)
- Active DoD sponsorship or government contract
- ITAR compliance for controlled data

**Security Controls**:
- MFA with CAC/PIV card required
- Conditional Access with device compliance required
- Advanced Threat Protection enabled
- Data Loss Prevention (DLP) policies enforced
- All data encrypted at rest and in transit
- Isolated from commercial cloud infrastructure

**Network Requirements**:
- **Must connect from US Government network or approved VPN**
- Direct internet access may be blocked
- Firewall rules must allow:
  - `https://graph.microsoft.us`
  - `https://login.microsoftonline.us`
  - `https://portal.azure.us`

**Access Controls**:
- Background checks required for all administrators
- US Person verification required
- Physical security controls for access locations
- Screened personnel only

**Data Classification**:
- Suitable for: CUI, ITAR controlled data, Export-controlled data
- Not suitable for: Classified information above Secret

**Audit and Monitoring**:
- Enhanced logging required
- All administrative actions audited
- Log retention minimum 1 year
- Security Information and Event Management (SIEM) integration

### DoD (Department of Defense) Tenants

**Compliance Level**: DoD IL5, DISA SRG

**Requirements**:
- DoD IL5 authorization
- **Active security clearance required** (Secret or higher)
- US Citizen required
- DoD sponsorship required

**Security Controls**:
- MFA with CAC card mandatory
- PKI certificates required
- Conditional Access with compliant device required
- Advanced Threat Protection with EDR
- All data encrypted with FIPS 140-2 compliant algorithms
- Completely isolated infrastructure

**Network Requirements**:
- **Must connect from DoD network infrastructure (SIPRNET or NIPRNET)**
- No direct internet access for management
- Firewall rules must allow:
  - `https://dod-graph.microsoft.us`
  - `https://login.microsoftonline.us`
  - `https://portal.azure.us`

**Access Controls**:
- Security clearance verification required
- Need-to-know basis access only
- Physical access restricted to SCIF or secure facility
- All access from government-issued devices only
- No BYOD or personal devices allowed

**Data Classification**:
- Suitable for: CUI, Secret, and classified data up to IL5
- Must follow data classification guidelines
- Proper labeling and handling required

**Audit and Monitoring**:
- Comprehensive logging required
- All actions audited and retained
- Real-time monitoring required
- Log retention minimum 3 years
- SIEM integration mandatory
- Incident response plan required

## Data Handling and Privacy

### Data Residency

| Tenant Type | Data Location | Isolation Level |
|-------------|--------------|-----------------|
| Commercial | Global | Standard |
| GCC | US | Logical separation |
| GCC High | US | Physical separation |
| DoD | US DoD datacenters | Complete isolation |

### Data at Rest

All tenant types encrypt data at rest using AES-256 encryption:
- Commercial: Microsoft-managed keys
- GCC: Microsoft-managed keys
- GCC High: Microsoft-managed or customer-managed keys
- DoD: Customer-managed keys required for classified data

### Data in Transit

All tenant types use TLS 1.2 or higher for data in transit:
- Commercial: TLS 1.2+
- GCC: TLS 1.2+
- GCC High: TLS 1.2+ with perfect forward secrecy
- DoD: TLS 1.3+ with FIPS 140-2 compliant ciphers

## Configuration Security

### Baseline Security Configurations

The Intune Hydration Kit includes security baselines appropriate for each tenant type:

**Commercial**:
- Standard Windows security baseline
- Microsoft Edge security baseline
- Microsoft Defender for Endpoint baseline

**GCC**:
- All Commercial baselines plus:
- Enhanced password policies
- Stricter device compliance requirements

**GCC High**:
- All GCC baselines plus:
- FIPS 140-2 compliance settings
- Enhanced encryption requirements
- ITAR compliance configurations

**DoD**:
- All GCC High baselines plus:
- DISA STIG compliance settings
- DoD security requirements
- Maximum security configurations

### Configuration Validation

Before importing configurations:

1. **Review all JSON files** for appropriate security settings
2. **Validate against your security policy**
3. **Test in non-production environment**
4. **Get security team approval** (especially for government tenants)
5. **Document all customizations**

### Secrets Management

**Never include secrets in configuration files**:
- No passwords
- No API keys
- No certificates
- No personal information

Use Azure Key Vault for secret management:
```powershell
# Example: Retrieve secret from Key Vault
$Secret = Get-AzKeyVaultSecret -VaultName "MyVault" -Name "IntuneSecret"
```

## Compliance Monitoring

### Audit Logging

Enable comprehensive audit logging:

```powershell
# Enable audit logs in Azure AD
Set-AzureADDirectorySetting -Id $SettingId -AuditLogEnabled $true

# Enable Intune audit logs
# (automatically enabled, retained for 1 year)
```

### Compliance Reports

Generate regular compliance reports:
- Device compliance status
- Configuration deployment status
- Security baseline compliance
- Conditional Access policy effectiveness

### Continuous Monitoring

Implement continuous monitoring:
- Azure Monitor for alerts
- Log Analytics for log aggregation
- Microsoft Sentinel for SIEM
- Compliance score tracking

## Incident Response

### Security Incident Procedures

1. **Detection**: Monitor for security events
2. **Containment**: Isolate affected systems
3. **Investigation**: Analyze logs and artifacts
4. **Remediation**: Apply fixes and updates
5. **Documentation**: Document incident and lessons learned

### Government Tenant Incidents

For GCC High and DoD tenants:
- Follow agency incident response procedures
- Report to appropriate authorities (CISA, DoD CERT)
- Maintain chain of custody for evidence
- Document all actions taken
- Conduct post-incident review

## Best Practices

### General Security

✅ **Do**:
- Use principle of least privilege
- Enable MFA for all accounts
- Regularly review access permissions
- Keep configurations version controlled
- Test all changes in non-production first
- Document all security decisions
- Regular security assessments

❌ **Don't**:
- Share credentials
- Disable security features
- Skip security reviews
- Use personal devices for administration (government)
- Store secrets in configuration files
- Ignore security warnings

### Government Tenants

Additional best practices:
- Maintain current security clearances
- Use government-issued devices only
- Connect from authorized networks only
- Follow data classification guidelines
- Report security concerns immediately
- Maintain audit trails
- Regular security training

## Vulnerability Management

### Keeping Up to Date

- Monitor Microsoft security advisories
- Subscribe to security mailing lists
- Apply security updates promptly
- Review configuration baselines quarterly
- Update PowerShell modules regularly

### Security Scanning

Run regular security scans:
```powershell
# Update Microsoft Graph modules
Update-Module Microsoft.Graph -Force

# Scan for vulnerabilities (use appropriate tools)
# Review security advisories
```

## Contact and Support

### Security Incidents

**Commercial**:
- Microsoft Support: https://support.microsoft.com
- Security Response Center: security@microsoft.com

**GCC**:
- Microsoft Government Support
- Agency security team

**GCC High/DoD**:
- Microsoft Government Support
- Agency security officer
- CISA: https://www.cisa.gov/report
- DoD CERT: https://www.cio.mil/contact-us.html

## Compliance Frameworks

### Applicable Standards

| Framework | Commercial | GCC | GCC High | DoD |
|-----------|-----------|-----|----------|-----|
| FedRAMP | - | Moderate | High | - |
| NIST 800-53 | Partial | Yes | Yes | Yes |
| DFARS | - | Partial | Yes | Yes |
| ITAR | - | - | Yes | Yes |
| DISA STIG | - | Partial | Partial | Yes |
| FIPS 140-2 | - | - | Yes | Yes |
| HIPAA | Yes | Yes | Yes | Yes |
| ISO 27001 | Yes | Yes | Yes | Yes |

## References

- [FedRAMP.gov](https://www.fedramp.gov/)
- [Microsoft Trust Center](https://www.microsoft.com/trust-center)
- [Azure Government Documentation](https://docs.microsoft.com/en-us/azure/azure-government/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [DoD Cloud Computing Security Requirements Guide](https://public.cyber.mil/dccs/dccs-documents/)
- [ITAR Regulations](https://www.pmddtc.state.gov/ddtc_public/ddtc_public?id=ddtc_public_portal_itar_landing)

## Version History

- **1.0.0** (2025-11-22): Initial security and compliance documentation
