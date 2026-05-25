function Add-HydrationStepResults {
    <#
    .SYNOPSIS
        Adds import step results to the results collection, surfacing nulls as warnings.
    .DESCRIPTION
        Iterates over step results and adds non-null items to $allResults.
        Logs a warning for any null result so issues are surfaced instead of silently dropped.
    .PARAMETER Results
        Array reference to accumulate results into.
    .PARAMETER StepResults
        The results returned by the import step.
    .PARAMETER StepName
        Name of the step for warning messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]$Results,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [array]$StepResults,

        [Parameter(Mandatory)]
        [string]$StepName
    )

    if ($null -eq $StepResults) {
        return
    }

    foreach ($result in $StepResults) {
        if ($null -ne $result) {
            $Results.Value += $result
        } else {
            Write-HydrationLog -Message "  Warning: $StepName step returned a null result object" -Level Warning
        }
    }
}
