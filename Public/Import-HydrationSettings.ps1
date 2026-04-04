function Import-HydrationSettings {
    <#
    .SYNOPSIS
        Imports and validates hydration settings
    .DESCRIPTION
        Loads settings from a JSON file.
    .PARAMETER Path
        Path to the settings file
    .EXAMPLE
        Import-HydrationSettings -Path './settings.json'
    .EXAMPLE
        $settings = Import-HydrationSettings -Path './settings.json'
        $settings.tenant.tenantId  # Access tenant ID from loaded settings
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

        # Validate required fields only when loading from file
        if (-not $settings.tenant.tenantId) {
            throw "Missing required field: tenant.tenantId"
        }

        Write-HydrationLog -Message "Settings loaded from: $Path" -Level Info
        return $settings
    } catch {
        Write-HydrationLog -Message "Failed to load settings: $_" -Level Error
        throw
    }
}
