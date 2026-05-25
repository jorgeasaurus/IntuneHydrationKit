function Test-HydrationHasPremiumP2License {
    <#
    .SYNOPSIS
        Checks whether tenant subscribed SKUs include an active Premium P2-capable service plan.
    .DESCRIPTION
        Evaluates enabled SKUs and returns true when any service plan name matches
        a Premium P2-compatible plan with provisioningStatus='Success'.
    .PARAMETER SubscribedSkus
        Array of subscribed SKU objects from Graph.
    .PARAMETER PremiumP2ServicePlans
        Service plan names considered Premium P2-capable.
    .EXAMPLE
        $hasPremiumP2 = Test-HydrationHasPremiumP2License -SubscribedSkus $subscribedSkus -PremiumP2ServicePlans (Get-PremiumP2ServicePlans)
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object[]]$SubscribedSkus,

        [Parameter(Mandatory)]
        [string[]]$PremiumP2ServicePlans
    )

    foreach ($sku in $SubscribedSkus) {
        if ($null -eq $sku) {
            continue
        }

        if ($sku.capabilityStatus -ne 'Enabled') {
            continue
        }

        foreach ($plan in @($sku.servicePlans)) {
            if ($null -eq $plan) {
                continue
            }

            if ($plan.servicePlanName -in $PremiumP2ServicePlans -and $plan.provisioningStatus -eq 'Success') {
                Write-Verbose "Found Premium P2 compatible license: $($plan.servicePlanName) in SKU $($sku.skuPartNumber)"
                return $true
            }
        }
    }

    return $false
}
