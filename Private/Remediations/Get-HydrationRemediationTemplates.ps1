function Get-HydrationRemediationTemplates {
    [CmdletBinding()]
    [OutputType([psobject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TemplatePath,

        [Parameter()]
        [string[]]$TemplateId
    )

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Container)) {
        return @()
    }

    $templates = [System.Collections.Generic.List[object]]::new()
    $templateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $displayNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($metadataFile in @(Get-ChildItem -LiteralPath $TemplatePath -Filter 'metadata.json' -File -Recurse | Sort-Object FullName)) {
        try {
            $metadata = Get-Content -LiteralPath $metadataFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        } catch {
            throw "Invalid remediation template metadata '$($metadataFile.FullName)': $($_.Exception.Message)"
        }

        foreach ($requiredProperty in @('templateId', 'displayName', 'publisher', 'description', 'runAsAccount', 'runAs32Bit', 'detectionScript')) {
            if (-not $metadata.Contains($requiredProperty) -or [string]::IsNullOrWhiteSpace([string]$metadata[$requiredProperty])) {
                throw "Remediation template '$($metadataFile.FullName)' is missing required property '$requiredProperty'."
            }
        }

        if ($metadata.runAsAccount -notin @('system', 'user')) {
            throw "Remediation template '$($metadataFile.FullName)' has unsupported runAsAccount '$($metadata.runAsAccount)'."
        }
        if ($metadata.runAs32Bit -isnot [bool]) {
            throw "Remediation template '$($metadataFile.FullName)' has non-Boolean runAs32Bit value."
        }

        if (-not $templateIds.Add([string]$metadata.templateId)) {
            throw "Remediation template '$($metadataFile.FullName)' has duplicate templateId '$($metadata.templateId)'."
        }

        if (-not $displayNames.Add([string]$metadata.displayName)) {
            throw "Remediation template '$($metadataFile.FullName)' has duplicate displayName '$($metadata.displayName)'."
        }

        $templateDirectory = $metadataFile.DirectoryName
        $detectionScriptPath = Resolve-HydrationTemplateChildPath -RootPath $templateDirectory -ChildPath ([string]$metadata.detectionScript) -PathLabel "Remediation template '$($metadataFile.FullName)' detection script"
        if (-not (Test-Path -LiteralPath $detectionScriptPath -PathType Leaf)) {
            throw "Remediation template '$($metadataFile.FullName)' detection script was not found: $detectionScriptPath"
        }

        $remediationScriptPath = $null
        if ($metadata.Contains('remediationScript') -and -not [string]::IsNullOrWhiteSpace([string]$metadata.remediationScript)) {
            $remediationScriptPath = Resolve-HydrationTemplateChildPath -RootPath $templateDirectory -ChildPath ([string]$metadata.remediationScript) -PathLabel "Remediation template '$($metadataFile.FullName)' remediation script"
            if (-not (Test-Path -LiteralPath $remediationScriptPath -PathType Leaf)) {
                throw "Remediation template '$($metadataFile.FullName)' remediation script was not found: $remediationScriptPath"
            }
        }

        $templates.Add([pscustomobject]@{
                TemplateId            = [string]$metadata.templateId
                DisplayName           = [string]$metadata.displayName
                Publisher             = [string]$metadata.publisher
                Description           = [string]$metadata.description
                RunAsAccount          = [string]$metadata.runAsAccount
                RunAs32Bit            = [bool]$metadata.runAs32Bit
                SortOrder             = if ($metadata.Contains('sortOrder')) { [int]$metadata.sortOrder } else { 1000 }
                TemplatePath          = $metadataFile.FullName
                DetectionScriptPath   = $detectionScriptPath
                RemediationScriptPath = $remediationScriptPath
            })
    }

    if ($TemplateId) {
        return @($templates | Where-Object { $_.TemplateId -in $TemplateId } | Sort-Object SortOrder, TemplateId)
    }

    return @($templates | Sort-Object SortOrder, TemplateId)
}
