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
        $schema = Get-HydrationSettingsSchema
        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $settings = $content | ConvertFrom-Json -AsHashtable
        $settings = Resolve-HydrationSettingsSchema -Settings $settings -Schema $schema

        Write-HydrationLog -Message "Settings loaded from: $Path" -Level Info
        return $settings
    } catch [System.Management.Automation.PipelineStoppedException] {
        throw
    } catch {
        Write-HydrationLog -Message "Failed to load settings: $_" -Level Error
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Failed to load settings from '$Path': $($_.Exception.Message)", $_.Exception),
            'SettingsLoadFailed',
            [System.Management.Automation.ErrorCategory]::ReadError,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
}
