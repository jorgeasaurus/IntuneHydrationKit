function ConvertTo-HydrationGroupBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$GroupDefinition,

        [Parameter(Mandatory)]
        [ValidateSet('Dynamic', 'Static')]
        [string]$GroupType
    )

    $body = @{
        displayName     = $GroupDefinition.displayName
        description     = New-HydrationDescription -ExistingText $GroupDefinition.description
        mailEnabled     = $false
        mailNickname    = New-HydrationGroupMailNickname -DisplayName $GroupDefinition.displayName
        securityEnabled = $true
    }

    if ($GroupType -eq 'Dynamic') {
        $body['groupTypes'] = @('DynamicMembership')
        $body['membershipRule'] = $GroupDefinition.membershipRule
        $body['membershipRuleProcessingState'] = 'On'
    }

    return $body
}
