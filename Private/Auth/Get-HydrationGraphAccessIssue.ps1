function Get-HydrationGraphAccessIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory)]
        [string]$Workload,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter(Mandatory)]
        [string]$RequiredScope,

        [string]$RoleHint = 'Use a Global Administrator account with active Intune service access.'
    )

    $statusCode = Get-GraphStatusCode -ErrorRecord $ErrorRecord
    $rawMessage = if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $ErrorRecord.ErrorDetails.Message
    } else {
        $ErrorRecord.Exception.Message
    }

    if (-not $statusCode) {
        if ($rawMessage -match '\b401\b|Unauthorized') {
            $statusCode = 401
        } elseif ($rawMessage -match '\b403\b|Forbidden|Access denied') {
            $statusCode = 403
        }
    }

    $statusText = if ($statusCode) { "HTTP $statusCode" } else { 'Graph access error' }

    return "$Workload access check failed: $statusText from $Endpoint. Required scope $RequiredScope is present; verify Intune service authorization/RBAC. $RoleHint"
}
