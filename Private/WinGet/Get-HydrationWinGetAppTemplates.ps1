function Get-HydrationWinGetAppTemplates {
    <#
    .SYNOPSIS
        Gets WinGet app templates from the repo-owned starter pack.
    .DESCRIPTION
        Loads WinGet app templates from Templates/MobileApps/Windows/WinGet/Apps and validates them
        against the repo-owned JSON schema. Optionally filters by template ID or a
        preset definition from Templates/MobileApps/Windows/WinGet/Presets.
    .PARAMETER TemplatePath
        The root WinGet template path. Defaults to Templates/MobileApps/Windows/WinGet.
    .PARAMETER TemplateId
        One or more template IDs to load.
    .PARAMETER PresetId
        Optional preset ID to resolve from Templates/MobileApps/Windows/WinGet/Presets.
    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [string[]]$TemplateId,

        [Parameter()]
        [string]$PresetId
    )

    function Get-TemplateErrorRecord {
        param(
            [Parameter(Mandatory)]
            [System.Exception]$Exception,

            [Parameter(Mandatory)]
            [string]$ErrorId,

            [Parameter(Mandatory)]
            [System.Management.Automation.ErrorCategory]$Category,

            [Parameter()]
            [object]$TargetObject
        )

        return [System.Management.Automation.ErrorRecord]::new(
            $Exception,
            $ErrorId,
            $Category,
            $TargetObject
        )
    }

    function Confirm-TemplatePath {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$ErrorId,

            [Parameter(Mandatory)]
            [string]$Message
        )

        if (-not (Test-Path -Path $Path)) {
            $errorRecord = Get-TemplateErrorRecord -Exception ([System.IO.FileNotFoundException]::new($Message)) `
                -ErrorId $ErrorId `
                -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound) `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    function Add-ResolvedTemplateId {
        param(
            [Parameter()]
            [AllowNull()]
            [string]$Id
        )

        if (-not [string]::IsNullOrWhiteSpace($Id) -and -not $resolvedTemplateIds.Contains($Id)) {
            $resolvedTemplateIds.Add($Id)
        }
    }

    function Test-WinGetTemplateJson {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$SchemaPath,

            [Parameter(Mandatory)]
            [string]$ValidationErrorId,

            [Parameter(Mandatory)]
            [string]$InvalidErrorId,

            [Parameter(Mandatory)]
            [string]$InvalidMessage
        )

        try {
            $templateIsValid = Test-Json -Path $Path -SchemaFile $SchemaPath -ErrorAction Stop
        } catch {
            $errorRecord = Get-TemplateErrorRecord -Exception $_.Exception `
                -ErrorId $ValidationErrorId `
                -Category ([System.Management.Automation.ErrorCategory]::InvalidData) `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if (-not $templateIsValid) {
            $errorRecord = Get-TemplateErrorRecord -Exception ([System.InvalidOperationException]::new($InvalidMessage)) `
                -ErrorId $InvalidErrorId `
                -Category ([System.Management.Automation.ErrorCategory]::InvalidData) `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath 'MobileApps/Windows/WinGet'
    }

    $appPath = Join-Path -Path $TemplatePath -ChildPath 'Apps'
    $presetPath = Join-Path -Path $TemplatePath -ChildPath 'Presets'
    $schemaPath = Join-Path -Path $TemplatePath -ChildPath 'Schemas/winGetAppTemplate.schema.json'
    $presetSchemaPath = Join-Path -Path $TemplatePath -ChildPath 'Schemas/winGetAppPreset.schema.json'

    Confirm-TemplatePath -Path $TemplatePath -ErrorId 'WinGetTemplateRootNotFound' -Message "WinGet template root not found: $TemplatePath"
    Confirm-TemplatePath -Path $appPath -ErrorId 'WinGetTemplateAppPathNotFound' -Message "WinGet template app path not found: $appPath"
    Confirm-TemplatePath -Path $schemaPath -ErrorId 'WinGetTemplateSchemaNotFound' -Message "WinGet app template schema not found: $schemaPath"
    Confirm-TemplatePath -Path $presetSchemaPath -ErrorId 'WinGetPresetSchemaNotFound' -Message "WinGet preset schema not found: $presetSchemaPath"

    $resolvedTemplateIds = [System.Collections.Generic.List[string]]::new()

    if ($PresetId) {
        Confirm-TemplatePath -Path $presetPath -ErrorId 'WinGetTemplatePresetPathNotFound' -Message "WinGet template preset path not found: $presetPath"

        $presetFile = Join-Path -Path $presetPath -ChildPath "$PresetId.json"
        Confirm-TemplatePath -Path $presetFile -ErrorId 'WinGetTemplatePresetNotFound' -Message "WinGet template preset not found: $presetFile"

        Test-WinGetTemplateJson -Path $presetFile `
            -SchemaPath $presetSchemaPath `
            -ValidationErrorId 'WinGetTemplatePresetValidationFailed' `
            -InvalidErrorId 'WinGetTemplatePresetInvalid' `
            -InvalidMessage "WinGet preset failed schema validation: $presetFile"

        $presetDefinition = Get-Content -Path $presetFile -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
        foreach ($presetTemplateId in $presetDefinition.appIds) {
            Add-ResolvedTemplateId -Id $presetTemplateId
        }
    }

    foreach ($requestedTemplateId in @($TemplateId)) {
        Add-ResolvedTemplateId -Id $requestedTemplateId
    }

    if ($resolvedTemplateIds.Count -gt 0) {
        $templateFiles = foreach ($currentTemplateId in $resolvedTemplateIds) {
            $currentTemplatePath = Join-Path -Path $appPath -ChildPath "$currentTemplateId.json"
            Confirm-TemplatePath -Path $currentTemplatePath `
                -ErrorId 'WinGetTemplateFileNotFound' `
                -Message "WinGet template file not found: $currentTemplatePath"

            Get-Item -Path $currentTemplatePath
        }
    } else {
        $templateFiles = Get-ChildItem -Path $appPath -Filter '*.json' -File | Sort-Object -Property Name
    }

    $templates = foreach ($templateFile in $templateFiles) {
        Test-WinGetTemplateJson -Path $templateFile.FullName `
            -SchemaPath $schemaPath `
            -ValidationErrorId 'WinGetTemplateValidationFailed' `
            -InvalidErrorId 'WinGetTemplateInvalid' `
            -InvalidMessage "WinGet template failed schema validation: $($templateFile.FullName)"

        $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
        $template | Add-Member -NotePropertyName 'TemplatePath' -NotePropertyValue $templateFile.FullName -Force

        if ($PresetId) {
            $template | Add-Member -NotePropertyName 'PresetId' -NotePropertyValue $PresetId -Force
        }

        $template
    }

    Write-Verbose "Loaded $($templates.Count) WinGet app template(s) from $TemplatePath"

    return $templates
}
