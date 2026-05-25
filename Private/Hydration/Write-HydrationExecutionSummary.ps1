function Write-HydrationExecutionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Results,

        [Parameter(Mandatory)]
        [datetime]$StartTime,

        [Parameter(Mandatory)]
        [bool]$WhatIfEnabled
    )

    $logParams = @{
        Message = 'Step 12: Generating Summary Report'
        Level   = 'Info'
    }
    Write-HydrationLog @logParams

    if ($Settings.reporting.outputPath) {
        $reportsPath = $Settings.reporting.outputPath
    } else {
        $tempBase = [System.IO.Path]::GetTempPath()
        $joinPathParams = @{
            Path      = $tempBase
            ChildPath = 'IntuneHydrationKit/Reports'
        }
        $reportsPath = Join-Path @joinPathParams
    }

    if (-not (Test-Path -Path $reportsPath)) {
        $newItemParams = @{
            Path     = $reportsPath
            ItemType = 'Directory'
            Force    = $true
            WhatIf   = $false
        }
        New-Item @newItemParams | Out-Null
    }

    $resultSummaryParams = @{
        Results = $Results
    }
    $summary = Get-ResultSummary @resultSummaryParams
    $joinPathParams = @{
        Path      = $reportsPath
        ChildPath = 'Hydration-Summary.md'
    }
    $reportPath = Join-Path @joinPathParams
    $jsonReportPath = $null
    $completionTime = Get-Date
    $timestamp = $completionTime.ToString('yyyy-MM-dd HH:mm:ss')
    $elapsedTime = $completionTime - $StartTime
    $elapsedTimeDisplay = '{0:00}:{1:00}:{2:00}' -f [Math]::Floor($elapsedTime.TotalHours), $elapsedTime.Minutes, $elapsedTime.Seconds
    $startedTimestamp = $StartTime.ToString('yyyy-MM-dd HH:mm:ss')

    $reportContent = @"
# Intune Hydration Summary

**Started:** $startedTimestamp
**Completed:** $timestamp
**Elapsed:** $elapsedTimeDisplay
**Tenant:** $($Settings.tenant.tenantId)
**Environment:** $($Settings.authentication.environment)
**Mode:** $(if ($WhatIfEnabled) { 'Dry-Run' } else { 'Live' })

## Summary

| Metric | Count |
|--------|-------|
| Total Operations | $($Results.Count) |
| Created | $($summary.Created) |
| Updated | $($summary.Updated) |
| Deleted | $($summary.Deleted) |
| Skipped | $($summary.Skipped) |
| Would Create | $($summary.WouldCreate) |
| Would Update | $($summary.WouldUpdate) |
| Would Delete | $($summary.WouldDelete) |
| Failed | $($summary.Failed) |

## Details by Type

"@

    $resultsByType = $Results | Group-Object -Property Type
    foreach ($typeGroup in $resultsByType) {
        $typeResults = $typeGroup.Group
        $created = ($typeResults | Where-Object { $_.Action -eq 'Created' }).Count
        $updated = ($typeResults | Where-Object { $_.Action -eq 'Updated' }).Count
        $deleted = ($typeResults | Where-Object { $_.Action -eq 'Deleted' }).Count
        $skipped = ($typeResults | Where-Object { $_.Action -eq 'Skipped' }).Count
        $wouldCreate = ($typeResults | Where-Object { $_.Action -eq 'WouldCreate' }).Count
        $wouldUpdate = ($typeResults | Where-Object { $_.Action -eq 'WouldUpdate' }).Count
        $wouldDelete = ($typeResults | Where-Object { $_.Action -eq 'WouldDelete' }).Count
        $failed = ($typeResults | Where-Object { $_.Action -eq 'Failed' }).Count

        $reportContent += @"

### $($typeGroup.Name)
- Created: $created
- Updated: $updated
- Deleted: $deleted
- Skipped: $skipped
- Would Create: $wouldCreate
- Would Update: $wouldUpdate
- Would Delete: $wouldDelete
- Failed: $failed

"@
    }

    if ($Results.Count -gt 0) {
        $reportContent += @"

## All Operations

| Timestamp | Type | Name | Action | ID | Details |
|-----------|------|------|--------|-----|---------|
"@

        $operationLines = foreach ($result in $Results) {
            if (-not $result.Name -and -not $result.Action) {
                continue
            }

            $timestampValue = if ($result.Timestamp) { $result.Timestamp } else { '' }
            $type = if ($result.PSObject.Properties['Type']) { $result.Type } else { '' }
            $name = if ($result.Name) { $result.Name } else { '' }
            $action = if ($result.Action) { $result.Action } else { '' }
            $id = if ($result.PSObject.Properties['Id']) { $result.Id } else { '' }
            $status = if ($result.Status) { $result.Status } else { '' }

            "| {0} | {1} | {2} | {3} | {4} | {5} |" -f $timestampValue, $type, $name, $action, $id, $status
        }

        $reportContent += "`n"
        $reportContent += ($operationLines -join "`n")
        $reportContent += "`n"
    }

    $reportContent += @"

## Important Notes

- **Conditional Access policies** were created in **DISABLED** state. Review and enable as needed.
- Review all configurations before enabling in production.

"@

    $outFileParams = @{
        FilePath = $reportPath
        Encoding = 'UTF8'
        WhatIf   = $false
    }
    $reportContent | Out-File @outFileParams
    $logParams = @{
        Message = "Summary report written to: $reportPath"
        Level   = 'Info'
    }
    Write-HydrationLog @logParams

    if ('json' -in $Settings.reporting.formats) {
        $joinPathParams = @{
            Path      = $reportsPath
            ChildPath = 'Hydration-Summary.json'
        }
        $jsonReportPath = Join-Path @joinPathParams
        @{
            Timestamp      = $timestamp
            Started        = $startedTimestamp
            Tenant         = $Settings.tenant.tenantId
            Environment    = $Settings.authentication.environment
            Mode           = if ($WhatIfEnabled) { 'DryRun' } else { 'Live' }
            ElapsedTime    = $elapsedTimeDisplay
            ElapsedSeconds = [Math]::Round($elapsedTime.TotalSeconds, 3)
            Summary        = $summary
            Results        = $Results
        } | ConvertTo-Json -Depth 10 | ForEach-Object {
            $jsonOutFileParams = @{
                FilePath = $jsonReportPath
                Encoding = 'UTF8'
                WhatIf   = $false
            }
            $_ | Out-File @jsonOutFileParams
        }
        $logParams = @{
            Message = "JSON report written to: $jsonReportPath"
            Level   = 'Info'
        }
        Write-HydrationLog @logParams
    }

    $logParams = @{
        Message = '=== Intune Hydration Kit Completed ==='
        Level   = 'Info'
    }
    Write-HydrationLog @logParams

    $summaryStatusLine = if ($WhatIfEnabled) {
        "Would Create: {0} | Would Update: {1} | Would Delete: {2} | Skipped: {3} | Failed: {4}" -f $summary.WouldCreate, $summary.WouldUpdate, $summary.WouldDelete, $summary.Skipped, $summary.Failed
    } else {
        "Created: {0} | Updated: {1} | Deleted: {2} | Skipped: {3} | Failed: {4}" -f $summary.Created, $summary.Updated, $summary.Deleted, $summary.Skipped, $summary.Failed
    }

    $summaryLines = @(
        ''
        (Format-HydrationDisplayMessage -Message 'Hydration Summary' -Style 'Section' -Emoji '📊')
        (Format-HydrationDisplayMessage -Message $summaryStatusLine -Style $(if ($WhatIfEnabled) { 'Info' } else { 'Success' }) -Emoji $(if ($WhatIfEnabled) { '🧪' } else { '✅' }))
        (Format-HydrationDisplayMessage -Message "Elapsed: $elapsedTimeDisplay" -Style 'Info' -Emoji '⏱️')
        (Format-HydrationDisplayMessage -Message "Reports: $reportPath" -Style 'Info' -Emoji '📝')
    )

    if ($jsonReportPath) {
        $summaryLines += Format-HydrationDisplayMessage -Message "JSON:    $jsonReportPath" -Style 'Info' -Emoji '🧾'
    }

    foreach ($summaryLine in $summaryLines) {
        Write-Information $summaryLine -InformationAction Continue
    }

    if ($summary.Failed -gt 0) {
        $logParams = @{
            Message = "Completed with $($summary.Failed) failures"
            Level   = 'Warning'
        }
        Write-HydrationLog @logParams
    } elseif ($WhatIfEnabled) {
        $logParams = @{
            Message = 'Dry-run completed in {0}: {1} would create, {2} would update, {3} would delete, {4} skipped' -f $elapsedTimeDisplay, $summary.WouldCreate, $summary.WouldUpdate, $summary.WouldDelete, $summary.Skipped
            Level   = 'Info'
        }
        Write-HydrationLog @logParams
    } else {
        $logParams = @{
            Message = 'Completed successfully in {0}: {1} created, {2} updated, {3} deleted, {4} skipped' -f $elapsedTimeDisplay, $summary.Created, $summary.Updated, $summary.Deleted, $summary.Skipped
            Level   = 'Info'
        }
        Write-HydrationLog @logParams
    }

    return @{
        Summary            = $summary
        ReportPath         = $reportPath
        JsonReportPath     = $jsonReportPath
        ElapsedTime        = $elapsedTime
        ElapsedTimeDisplay = $elapsedTimeDisplay
    }
}

