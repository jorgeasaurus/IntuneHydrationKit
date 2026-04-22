# Maintainability Task List

1. **Done** - Break `Invoke-IntuneHydration` into private orchestration helpers to separate settings normalization, platform filtering, step execution support, and summary/report generation.
2. **Done** - Convert the recent multi-parameter helper/orchestrator function calls to splat-based calls for consistency and readability.
3. Validate settings files against `settings.schema.json` at runtime instead of only checking `tenant.tenantId`.
4. Centralize Graph endpoint and `@odata.type` routing metadata shared by baseline importers.
5. Reduce reliance on mutable script-scoped state by wrapping shared module state behind focused helpers or context objects.
6. Standardize user-facing output around PowerShell streams and reserve `Write-Host` for intentional console UI.
7. Add template contract tests for bundled JSON so payload-shape regressions are caught before Graph import runs.
