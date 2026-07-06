function Invoke-HydrationDeleteCandidates {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Candidates,

        [Parameter(Mandatory)]
        [string]$ResultType,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $results = @()
    if ($Candidates.Count -eq 0) {
        return $results
    }

    if (-not $PSCmdlet.ShouldProcess("$($Candidates.Count) $Label", 'Delete')) {
        if ($WhatIfPreference) {
            foreach ($candidate in $Candidates) {
                Write-HydrationLog -Message "  WouldDelete: $($candidate.Name)" -Level Info
                $results += New-HydrationResult -Name $candidate.Name -Type $ResultType -Action 'WouldDelete' -Status 'DryRun'
            }
        }
        return $results
    }

    return Invoke-GraphBatchOperation -Items $Candidates -Operation 'DELETE' -ResultType $ResultType
}
