# Intune Hydration Kit

<p class="ihk-subtitle">Automate. Hydrate. Protect. A production-first toolkit for Microsoft Intune baseline deployment.</p>

<div class="ihk-badges">
  <img src="https://img.shields.io/github/stars/jorgeasaurus/IntuneHydrationKit?style=social" alt="GitHub Stars" />
  <img src="https://img.shields.io/powershellgallery/v/IntuneHydrationKit?label=PSGallery&color=0D8BFF" alt="PowerShell Gallery Version" />
  <img src="https://img.shields.io/powershellgallery/dt/IntuneHydrationKit?label=Downloads&color=08C7FF" alt="PowerShell Gallery Downloads" />
  <img src="https://img.shields.io/github/actions/workflow/status/jorgeasaurus/IntuneHydrationKit/ci.yml?label=CI" alt="CI Status" />
</div>

<div class="ihk-logo-card">
  <img src="assets/IHTLogoClearLight.png" alt="Intune Hydration Kit logo" class="ihk-logo" />
  <p>This documentation site provides module guidance and complete PlatyPS command reference pages.</p>
</div>

## Getting Started

Install and inspect commands:

```powershell
Install-Module -Name IntuneHydrationKit -Scope CurrentUser
Get-Command -Module IntuneHydrationKit
```

Start here:

- [Invocation Examples](Invocation-Examples.md)
- [Invoke-IntuneHydration](platyps/Invoke-IntuneHydration.md)
- [Connect-IntuneHydration](platyps/Connect-IntuneHydration.md)

## Command Reference

Core orchestration:

- [Invoke-IntuneHydration](platyps/Invoke-IntuneHydration.md)
- [Import-HydrationSettings](platyps/Import-HydrationSettings.md)
- [Test-IntunePrerequisites](platyps/Test-IntunePrerequisites.md)

Import commands:

- [Import-IntuneBaseline](platyps/Import-IntuneBaseline.md)
- [Import-CISBaseline](platyps/Import-CISBaseline.md)
- [Import-IntuneCompliancePolicy](platyps/Import-IntuneCompliancePolicy.md)
- [Import-IntuneDeviceFilter](platyps/Import-IntuneDeviceFilter.md)
- [Import-IntuneAppProtectionPolicy](platyps/Import-IntuneAppProtectionPolicy.md)
- [Import-IntuneNotificationTemplate](platyps/Import-IntuneNotificationTemplate.md)
- [Import-IntuneEnrollmentProfile](platyps/Import-IntuneEnrollmentProfile.md)
- [Import-IntuneConditionalAccessPolicy](platyps/Import-IntuneConditionalAccessPolicy.md)
- [Import-IntuneMobileApp](platyps/Import-IntuneMobileApp.md)
- [Import-IntuneWinGetApp](platyps/Import-IntuneWinGetApp.md)

Helpers:

- [Initialize-HydrationLogging](platyps/Initialize-HydrationLogging.md)
- [Write-HydrationLog](platyps/Write-HydrationLog.md)
- [New-IntuneDynamicGroup](platyps/New-IntuneDynamicGroup.md)
- [New-IntuneStaticGroup](platyps/New-IntuneStaticGroup.md)
- [Get-OpenIntuneBaseline](platyps/Get-OpenIntuneBaseline.md)
