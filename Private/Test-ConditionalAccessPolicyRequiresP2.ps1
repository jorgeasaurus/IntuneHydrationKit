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

    # Check if policy has conditions
    if (-not $Policy.conditions) {
        return $false
    }

    $conditions = $Policy.conditions

    # Check for sign-in risk levels
    if ($conditions.signInRiskLevels -and
        $conditions.signInRiskLevels -is [array] -and
        $conditions.signInRiskLevels.Count -gt 0) {
        Write-Verbose "Policy requires P2: uses signInRiskLevels"
        return $true
    }

    # Check for user risk levels
    if ($conditions.userRiskLevels -and
        $conditions.userRiskLevels -is [array] -and
        $conditions.userRiskLevels.Count -gt 0) {
        Write-Verbose "Policy requires P2: uses userRiskLevels"
        return $true
    }

    # Check for insider risk levels (string value, not array)
    if ($null -ne $conditions.insiderRiskLevels -and
        $conditions.insiderRiskLevels -ne "null" -and
        $conditions.insiderRiskLevels.ToString().Trim() -ne "") {
        Write-Verbose "Policy requires P2: uses insiderRiskLevels"
        return $true
    }

    # Check for agent identity risk levels (can be string or array)
    if ($null -ne $conditions.agentIdRiskLevels) {
        # Handle array format
        if ($conditions.agentIdRiskLevels -is [array] -and $conditions.agentIdRiskLevels.Count -gt 0) {
            Write-Verbose "Policy requires P2: uses agentIdRiskLevels (array)"
            return $true
        }
        # Handle string format
        if ($conditions.agentIdRiskLevels -is [string] -and $conditions.agentIdRiskLevels.Trim() -ne "") {
            Write-Verbose "Policy requires P2: uses agentIdRiskLevels (string)"
            return $true
        }
    }

    # Check for service principal risk levels (can be string or array)
    if ($null -ne $conditions.servicePrincipalRiskLevels) {
        # Handle array format
        if ($conditions.servicePrincipalRiskLevels -is [array] -and $conditions.servicePrincipalRiskLevels.Count -gt 0) {
            Write-Verbose "Policy requires P2: uses servicePrincipalRiskLevels (array)"
            return $true
        }
        # Handle string format
        if ($conditions.servicePrincipalRiskLevels -is [string] -and $conditions.servicePrincipalRiskLevels.Trim() -ne "") {
            Write-Verbose "Policy requires P2: uses servicePrincipalRiskLevels (string)"
            return $true
        }
    }

    return $false
}
