function Test-ConditionalAccessPolicyRequiresPreview {
    <#
    .SYNOPSIS
        Checks if a Conditional Access policy requires private preview features
    .DESCRIPTION
        Analyzes a Conditional Access policy object to determine if it uses features
        that require explicit tenant authorization for private preview access.

        Known private preview features:
        - Account Recovery (urn:user:accountrecovery) - requires AccountRecovery preview authorization
    .PARAMETER Policy
        The Conditional Access policy object to check
    .EXAMPLE
        $policy = Get-Content -Path "policy.json" | ConvertFrom-Json
        Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
    .OUTPUTS
        System.String - Returns the preview feature name if required, $null otherwise
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Policy
    )

    # Check if policy has conditions
    if (-not $Policy.conditions) {
        return $null
    }

    $conditions = $Policy.conditions

    # Check for Account Recovery user action (private preview)
    if ($conditions.applications -and $conditions.applications.includeUserActions) {
        $userActions = $conditions.applications.includeUserActions

        if ($userActions -contains "urn:user:accountrecovery") {
            Write-Verbose "Policy requires preview: AccountRecovery (urn:user:accountrecovery)"
            return "AccountRecovery"
        }
    }

    # Check for other potential preview features
    # Add more preview feature checks here as they are discovered

    return $null
}
