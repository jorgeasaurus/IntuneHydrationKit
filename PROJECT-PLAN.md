# Intune-Hydration-Kit — Project Plan

## Goals and Scope
- Hydrate a new Intune tenant with baseline policies, compliance pack, enrollment profiles, dynamic groups, security baselines, and a disabled conditional access starter pack.
- PowerShell-only implementation using Microsoft Graph and IntuneManagement; no agents, CI, GitOps, or deployment extras.
- Idempotent create-or-update behavior; produce a single run summary at `Reports/Hydration-Summary.md`.

## Repository Layout (proposed)
- `Scripts/Invoke-IntuneHydration.ps1` — entrypoint orchestrator.
- `Scripts/Modules/Helpers.psm1` — auth, Graph wrapper with retry, logging, templating, upsert helpers.
- `Templates/OpenIntuneBaseline/` — upstream baseline JSON.
- `Templates/Baselines/Compliance/` — compliance policy templates.
- `Templates/Enrollment/` — Autopilot and MDM enrollment profile templates.
- `Templates/DynamicGroups/` — OData rules for required groups.
- `Templates/Baselines/Security/` — Windows, Edge, M365 Apps security baselines.
- `Templates/ConditionalAccess/` — starter pack CA policies (all forced disabled).
- `Reports/` — generated run reports.
- `settings.example.json` — sample inputs (tenant, auth mode, toggles).
- `README.md` — usage, prerequisites, troubleshooting.

## Workstream Breakdown
1) **Scaffold and Config**
   - Create folders above; define settings schema (tenant, auth mode, ABM flag, dry-run).
   - Add basic logging (console + structured), error aggregation, and WhatIf/dry-run mode.
2) **Authentication and Pre-flight**
   - Support user/password and certificate auth; call `Connect-MgGraph` with required scopes.
   - Validate Intune licenses and MDM authority; exit with guidance if missing.
3) **Dynamic Group Suite**
   - Create OS, manufacturer, Autopilot, compliance-state groups; optional model groups if devices exist.
   - Store name-to-ID map for later assignments.
4) **OpenIntuneBaseline Import**
   - Pull templates from `SkipToTheEndpoint/OpenIntuneBaseline` and ensure IntuneManagement module is present.
   - Upsert profiles; capture create/update/skip counts.
5) **Compliance Baseline Pack**
   - Load templates from `Templates/Baselines/Compliance`; create/update; assign to platform groups.
6) **Enrollment Profiles**
   - Windows Autopilot deployment profile, ESP, optional naming; macOS/iOS profiles gated on ABM flag.
   - Assign to appropriate groups.
7) **Security Baselines**
   - Import Windows 10/11, Edge, and M365 Apps baselines; assign to OS groups.
8) **Conditional Access Starter Pack**
   - Import templates, force `"state": "disabled"`; include MFA, compliant-device, legacy auth block, admin protection, break-glass bypass.
9) **Reporting**
   - Aggregate counts, IDs, assignments, errors into `Reports/Hydration-Summary.md`.
   - Optional CSV/JSON artifacts for auditing.

## Execution Flow (script outline)
1. Parse settings and switches (WhatIf, force update).
2. Authenticate and run pre-flight checks.
3. Ensure dynamic groups, capture IDs.
4. Import baselines (OpenIntune + compliance + security).
5. Apply enrollment profiles.
6. Import CA starter pack (all disabled).
7. Write report and exit code based on critical errors.

## Quality and Testing
- Pester unit tests for helper functions (templating, upsert decision logic, retry).
- Lint via ScriptAnalyzer; validate templates load and required tokens resolve.
- Dry-run mode that evaluates templates and targets without writing to Graph.
- Smoke test against a non-production tenant using least-privilege account.

## Risks and Mitigations
- Transient Graph errors: implement retry with backoff and idempotent upsert.
- Mis-targeted assignments: validate dynamic group rules and confirm IDs before assignment.
- Overwrites: support `force` flag; otherwise only update when template drift is detected.
- Missing prerequisites: early exits with actionable messages for licenses/MDM authority/module availability.

## Open Decisions
- Whether to include macOS/iOS enrollment profiles by default or gate on explicit ABM toggle.
- Targeting strategy for CA policies (unassigned vs all users with exclusions).
- Versioning approach for templates (pin upstream commits vs latest pull each run).
