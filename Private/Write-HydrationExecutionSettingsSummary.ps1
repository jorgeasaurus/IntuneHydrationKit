function Write-HydrationExecutionSettingsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    $writeHostParams = @{
        Object            = "Target Tenant: $(Get-ObfuscatedTenantId -TenantId $Settings.tenant.tenantId)"
        InformationAction = 'Continue'
    }
    Write-Host @writeHostParams
    if ($Settings.tenant.tenantName) {
        $writeHostParams = @{
            Object            = "Tenant Name: $($Settings.tenant.tenantName)"
            InformationAction = 'Continue'
        }
        Write-Host @writeHostParams
    }

    $writeHostParams = @{
        Object            = "Authentication Mode: $($Settings.authentication.mode)"
        InformationAction = 'Continue'
    }
    Write-Host @writeHostParams
    $writeHostParams = @{
        Object            = 'Options:'
        InformationAction = 'Continue'
    }
    Write-Host @writeHostParams
    $writeHostParams = @{
        Object            = ($Settings.options | Out-String)
        InformationAction = 'Continue'
    }
    Write-Host @writeHostParams
    $writeHostParams = @{
        Object            = 'Imports Enabled:'
        InformationAction = 'Continue'
    }
    Write-Host @writeHostParams
    $writeHostParams = @{
        Object            = ($Settings.imports | Out-String)
        InformationAction = 'Continue'
    }
    Write-Host @writeHostParams
    $writeHostParams = @{
        Object            = "Platform Filter: $($Settings.platforms -join ', ')"
        InformationAction = 'Continue'
    }
    Write-Host @writeHostParams
}
