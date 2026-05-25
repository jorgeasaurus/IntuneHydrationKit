function Test-ConditionalAccessPolicyRequiresP2 {
    <#
    .SYNOPSIS
        Checks if a Conditional Access policy requires Premium P2 licensing
    .DESCRIPTION
        Analyzes a Conditional Access policy object to determine if it uses features
        that require Azure AD Premium P2 licensing. These features include:
        - Sign-in risk levels (signInRiskLevels)
        - User risk levels (userRiskLevels)
        - Insider risk levels (insiderRiskLevels)
        - Agent identity risk levels (agentIdRiskLevels)
        - Service principal risk levels (servicePrincipalRiskLevels)
    .PARAMETER Policy
        The Conditional Access policy object to check
    .EXAMPLE
        $policy = Get-Content -Path "policy.json" | ConvertFrom-Json
        Test-ConditionalAccessPolicyRequiresP2 -Policy $policy
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Policy
    )

    if (-not $Policy.conditions) {
        return $false
    }

    $conditions = $Policy.conditions

    if (Test-HydrationNonEmptyArrayValue -Value $conditions.signInRiskLevels) {
        Write-Verbose "Policy requires P2: uses signInRiskLevels"
        return $true
    }

    if (Test-HydrationNonEmptyArrayValue -Value $conditions.userRiskLevels) {
        Write-Verbose "Policy requires P2: uses userRiskLevels"
        return $true
    }

    if (Test-HydrationNonEmptyStringValue -Value $conditions.insiderRiskLevels) {
        Write-Verbose "Policy requires P2: uses insiderRiskLevels"
        return $true
    }

    if (Test-HydrationNonEmptyArrayValue -Value $conditions.agentIdRiskLevels) {
        Write-Verbose "Policy requires P2: uses agentIdRiskLevels (array)"
        return $true
    }

    if (Test-HydrationNonEmptyStringValue -Value $conditions.agentIdRiskLevels) {
        Write-Verbose "Policy requires P2: uses agentIdRiskLevels (string)"
        return $true
    }

    if (Test-HydrationNonEmptyArrayValue -Value $conditions.servicePrincipalRiskLevels) {
        Write-Verbose "Policy requires P2: uses servicePrincipalRiskLevels (array)"
        return $true
    }

    if (Test-HydrationNonEmptyStringValue -Value $conditions.servicePrincipalRiskLevels) {
        Write-Verbose "Policy requires P2: uses servicePrincipalRiskLevels (string)"
        return $true
    }

    return $false
}
