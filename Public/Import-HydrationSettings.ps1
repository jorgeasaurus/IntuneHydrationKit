function Import-HydrationSettings {
    <#
    .SYNOPSIS
        Imports and validates hydration settings
    .PARAMETER Path
        Path to the settings file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path
    )

    try {
        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $settings = $content | ConvertFrom-Json -AsHashtable

        # Validate required fields
        if (-not $settings.tenant.tenantId) {
            throw "Missing required field: tenant.tenantId"
        }

        Write-HydrationLog -Message "Settings loaded from: $Path" -Level Info
        return $settings
    }
    catch {
        Write-HydrationLog -Message "Failed to load settings: $_" -Level Error
        throw
    }
}
