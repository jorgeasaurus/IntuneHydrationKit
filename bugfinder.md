# Bug Finder

Status: all actionable findings in this file are addressed in the working tree.

## Cleanup Items

- Resolved: collapsed the mobile app, name-only, and WinGet delete decisions into `Resolve-HydrationDeleteDecision`.
- Resolved: removed the standalone delete-decision factory; callers now use the shared decision shape.
- Resolved: removed redundant locally-generated batch-entry defense while keeping missing and unmatched Graph response handling.
- Resolved: moved workload catalog consistency checks to Pester contract tests; runtime planning only computes the plan.
- Resolved: orchestration assigns `$settings.imports = $workloadPlan.Imports` and does not keep a duplicate public `$effectiveImports` state.
- Resolved: CIS platform resolution inlines the unique platform selection.

## Bug Hunt Findings

1. Resolved: Autopilot and ESP imports skip creation on any matching existing profile, including untagged name matches.
2. Resolved: `Invoke-HydrationGraphRequest` treats status code `0` as a concrete non-retryable status.
3. Resolved: compliance import warns on filename/metadata platform disagreement and prevents Windows-scoped templates from routing to the Linux endpoint.
4. Resolved: WinGet detection and requirement `ScriptFile` paths must resolve under the template root.
5. Resolved: group `mailNickname` generation appends a deterministic hash suffix to avoid sanitizer collisions.
6. Resolved: Graph helpers use `MaxRetries` as retries after the initial attempt.

## Verification

- Focused final regression set: 119 passed, 0 failed.
- Full test task: 1067 passed, 0 failed, 2 skipped.
- Analyzer: 0 errors, 178 warning-class findings.
- Build/package smoke, manifest/import smoke, export sync, stale-reference check, and `git diff --check`: passed.
- Final parallel reviewers: no material findings.

Rejected reviewer claims remain non-actionable.
