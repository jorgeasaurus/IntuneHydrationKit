function Get-HydrationSettingsSchema {
    [CmdletBinding()]
    param()

    if ($script:ModuleRoot -and (Test-Path -Path $script:ModuleRoot)) {
        $schemaPath = Join-Path -Path $script:ModuleRoot -ChildPath 'settings.schema.json'
    } else {
        # Walk up two levels from Private/Configuration/ to the repo root
        $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $schemaPath = Join-Path -Path $repoRoot -ChildPath 'settings.schema.json'
    }

    if (-not (Test-Path -Path $schemaPath)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Settings schema not found at '$schemaPath'."),
            'SettingsSchemaNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $schemaPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $schemaContent = Get-Content -Path $schemaPath -Raw -Encoding utf8 -ErrorAction Stop
    return $schemaContent | ConvertFrom-Json -AsHashtable
}
