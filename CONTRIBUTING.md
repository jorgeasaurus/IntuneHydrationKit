# Contributing to Intune Hydration Kit

Thank you for your interest in contributing to the Intune Hydration Kit! This document provides guidelines and instructions for contributing.

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow security best practices

## How to Contribute

### Reporting Issues

If you find a bug or have a feature request:

1. **Search existing issues** to avoid duplicates
2. **Create a new issue** with a clear title and description
3. **Include relevant details:**
   - PowerShell version
   - Tenant type (Commercial, GCC, GCC High, DoD)
   - Error messages and log files
   - Steps to reproduce

### Submitting Changes

1. **Fork the repository**
2. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
4. **Test thoroughly**
5. **Commit with clear messages:**
   ```bash
   git commit -m "Add feature: description of feature"
   ```
6. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```
7. **Create a Pull Request**

## Contribution Guidelines

### PowerShell Code Style

Follow these PowerShell best practices:

```powershell
# Use approved verbs
Get-Something
Set-Something
New-Something

# Use PascalCase for functions and parameters
function Get-TenantConfiguration {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantId
    )
}

# Include comment-based help
<#
.SYNOPSIS
    Brief description of function
.DESCRIPTION
    Detailed description
.PARAMETER ParameterName
    Description of parameter
.EXAMPLE
    Example of how to use
#>

# Use try/catch for error handling
try {
    # Code that might fail
}
catch {
    Write-Error "Descriptive error message: $($_.Exception.Message)"
}

# Use Write-Verbose for detailed logging
Write-Verbose "Connecting to tenant: $TenantId"
```

### Configuration Files

When adding new configuration files:

1. **Use valid JSON format**
2. **Remove auto-generated properties:**
   - id
   - createdDateTime
   - lastModifiedDateTime
3. **Include required properties:**
   - @odata.type
   - displayName
   - description
4. **Test the configuration** in a dev/test environment
5. **Document the configuration** in README.md

Example:
```json
{
  "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
  "displayName": "Descriptive Name",
  "description": "Clear description of what this configures",
  "passwordRequired": true
}
```

### Documentation

When updating documentation:

- Use clear, concise language
- Include examples for each scenario
- Update all affected files (README, EXAMPLES, QUICKSTART)
- Check spelling and grammar
- Use markdown formatting consistently

### Testing

Before submitting:

1. **Run the validation script:**
   ```powershell
   .\Test-IntuneHydrationKit.ps1
   ```

2. **Test with WhatIf:**
   ```powershell
   .\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "test-id" -WhatIf
   ```

3. **Verify JSON syntax:**
   ```powershell
   Get-Content YourConfig.json | ConvertFrom-Json
   ```

4. **Test in a dev/test environment** if possible

## Types of Contributions

### New Configuration Files

We welcome new baseline configurations:

- Compliance policies for new platforms
- Configuration profiles for specific scenarios
- Dynamic groups for common use cases
- Security baselines

**Requirements:**
- Must be tested in at least one environment
- Must include appropriate documentation
- Must not contain sensitive data
- Must use Microsoft Graph API format

### Module Improvements

Enhancements to PowerShell modules:

- Better error handling
- Additional validation
- Performance improvements
- New features

**Requirements:**
- Maintain backward compatibility
- Include comment-based help
- Follow existing code style
- Add validation tests

### Documentation Improvements

Documentation is crucial:

- Fix typos and errors
- Add missing examples
- Clarify confusing sections
- Update for new features

### Bug Fixes

When fixing bugs:

1. **Reference the issue number** in commit message
2. **Describe the problem** and solution
3. **Include test cases** if applicable
4. **Update documentation** if behavior changes

## Tenant-Specific Contributions

### Government Tenant Configurations

When contributing government tenant configurations:

- **Do not include classified information**
- **Follow your organization's security policies**
- **Ensure proper authorization** before sharing
- **Remove any agency-specific identifiers**
- **Document compliance requirements**

### GCC High and DoD Contributions

Special considerations:

- Verify you have authorization to share
- Remove all CUI or classified markings
- Ensure configurations are generalizable
- Follow ITAR and export control regulations

## Security Guidelines

### Security Best Practices

- Never commit credentials, API keys, or secrets
- Review code for security vulnerabilities
- Use parameterized inputs to prevent injection
- Validate all user inputs
- Handle sensitive data appropriately
- Follow least privilege principle

### Reporting Security Issues

**Do not open public issues for security vulnerabilities.**

Instead:
1. Email security concerns to the maintainers privately
2. Include detailed description of vulnerability
3. Provide steps to reproduce if possible
4. Allow reasonable time for fix before disclosure

## Review Process

### What to Expect

1. **Initial review** within 1-2 weeks
2. **Feedback and discussion** on changes
3. **Requested changes** if needed
4. **Approval and merge** once requirements are met

### Review Criteria

We evaluate contributions based on:

- Code quality and style
- Test coverage
- Documentation completeness
- Security considerations
- Compatibility with existing code
- Value to the community

## Getting Help

If you need assistance:

- Review existing documentation
- Check closed issues for similar problems
- Ask questions in issue comments
- Reach out to maintainers

## Recognition

Contributors will be:

- Listed in commit history
- Acknowledged in release notes
- Credited for significant contributions

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## Examples of Good Contributions

### Example 1: Adding a New Compliance Policy

```powershell
# 1. Create the configuration file
{
  "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
  "displayName": "Windows 10 - Healthcare Compliance",
  "description": "HIPAA compliant baseline for healthcare organizations",
  "passwordRequired": true,
  "passwordMinimumLength": 12,
  "storageRequireEncryption": true,
  "bitLockerEnabled": true
}

# 2. Add documentation in Configurations/README.md
# 3. Test with validation script
# 4. Submit PR with clear description
```

### Example 2: Improving Error Handling

```powershell
# Before
$Config = Get-Content $Path | ConvertFrom-Json

# After
try {
    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }
    $Config = Get-Content $Path -Raw | ConvertFrom-Json
    if (-not $Config.displayName) {
        throw "Configuration missing required property: displayName"
    }
}
catch {
    Write-Error "Failed to load configuration: $($_.Exception.Message)"
    return $null
}
```

### Example 3: Documentation Improvement

```markdown
# Before
Run the script with parameters.

# After
Run the hydration script with the appropriate parameters for your tenant type:

## Commercial Tenant
```powershell
.\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "your-tenant-id"
```

## GCC High Tenant
```powershell
.\Start-IntuneHydration.ps1 -TenantType GCCHigh -TenantId "your-tenant-id"
```

Make sure you have the required permissions before running.
```

## Questions?

If you have questions about contributing:

- Open an issue with the "question" label
- Review the [README.md](README.md) and [EXAMPLES.md](EXAMPLES.md)
- Check existing pull requests for similar contributions

Thank you for contributing to the Intune Hydration Kit!
