function New-HydrationExecutionSetting {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$TenantName,

        [Parameter(Mandatory)]
        [ValidateSet('interactive', 'clientSecret')]
        [string]$AuthenticationMode,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [object]$ClientSecret,

        [Parameter()]
        [string]$Environment = 'Global',

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Options,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Imports,

        [Parameter()]
        [string[]]$Platforms = @('All'),

        [Parameter()]
        [string]$ReportOutputPath,

        [Parameter()]
        [string[]]$ReportFormats = @('markdown'),

        [Parameter()]
        [System.Collections.IDictionary]$MobileApps
    )

    $mobileAppSettings = @{
        presetId    = $null
        templateIds = @()
        remediation = @{
            enabled = $true
        }
    }

    if ($MobileApps) {
        if ($MobileApps.Contains('presetId')) {
            $mobileAppSettings.presetId = $MobileApps.presetId
        }

        if ($MobileApps.Contains('templateIds') -and $null -ne $MobileApps.templateIds) {
            $mobileAppSettings.templateIds = @($MobileApps.templateIds)
        }

        if ($MobileApps.Contains('remediation') -and $MobileApps.remediation -and $MobileApps.remediation.Contains('enabled')) {
            $mobileAppSettings.remediation.enabled = [bool]$MobileApps.remediation.enabled
        }
    }

    $importSettings = @{}
    foreach ($importKey in $Imports.Keys) {
        $importSettings[$importKey] = [bool]$Imports[$importKey]
    }

    $resolvedEnvironment = if ($Environment) { $Environment } else { 'Global' }

    return @{
        tenant         = @{
            tenantId   = $TenantId
            tenantName = $TenantName
        }
        authentication = @{
            mode         = $AuthenticationMode
            clientId     = $ClientId
            clientSecret = $ClientSecret
            environment  = $resolvedEnvironment
        }
        options        = @{
            create       = [bool]$Options.create
            delete       = [bool]$Options.delete
            force        = [bool]$Options.force
            dryRun       = [bool]$Options.dryRun
            verbose      = [bool]$Options.verbose
            forceConsent = [bool]$Options.forceConsent
        }
        imports        = $importSettings
        mobileApps     = $mobileAppSettings
        reporting      = @{
            outputPath = if ($ReportOutputPath) { $ReportOutputPath } else { $null }
            formats    = if ($ReportFormats) { $ReportFormats } else { @('markdown') }
        }
        platforms      = if ($Platforms) { $Platforms } else { @('All') }
    }
}
