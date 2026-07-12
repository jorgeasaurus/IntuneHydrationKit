function Get-IntuneProactiveRemediationAvailability {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Invoke-HydrationGraphRequest -Method GET -Uri "beta/deviceManagement/deviceHealthScripts?`$top=1" | Out-Null
        Write-Debug 'Proactive remediation availability check passed.'
        return [pscustomobject]@{
            IsAvailable = $true
            Status      = 'Available'
            Message     = 'Proactive remediations are available.'
        }
    } catch {
        $statusCode = Get-GraphStatusCode -ErrorRecord $_
        $errorMessage = Get-GraphErrorMessage -ErrorRecord $_

        $isPermissionIssue = $statusCode -eq 403 -or
        $errorMessage -match 'forbidden|access denied|insufficient privileges|insufficient permission'
        $isFeatureUnavailable = $statusCode -eq 404 -or
        $errorMessage -match 'license|not enabled|not found'

        if ($isPermissionIssue) {
            Write-Debug "Proactive remediation availability check failed due to permissions: $errorMessage"
            return [pscustomobject]@{
                IsAvailable = $false
                Status      = 'InsufficientPermissions'
                Message     = 'Insufficient permissions to access device health scripts.'
            }
        }

        if ($isFeatureUnavailable) {
            Write-Debug "Proactive remediation availability check failed because the feature is unavailable: $errorMessage"
            return [pscustomobject]@{
                IsAvailable = $false
                Status      = 'FeatureUnavailable'
                Message     = 'Device health scripts are not available in this tenant.'
            }
        }

        throw
    }
}
