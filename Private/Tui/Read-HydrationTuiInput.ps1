function Read-HydrationTuiInput {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $value = Read-Host -Prompt "$Prompt (q to cancel)"
    if (Test-HydrationTuiCancelValue -Value $value) {
        return [pscustomobject]@{
            Cancelled = $true
            Value     = $null
        }
    }

    return [pscustomobject]@{
        Cancelled = $false
        Value     = $value
    }
}
