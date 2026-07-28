function New-HydrationRemediationBody {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [bool]$IncludeCreateOnlyProperties
    )

    $detectionScriptContent = Get-Content -LiteralPath $Template.DetectionScriptPath -Raw -Encoding utf8
    $null = Save-HydrationGeneratedScript -RelativePath "Remediations/$($Template.TemplateId)/$([System.IO.Path]::GetFileName($Template.DetectionScriptPath))" -SourcePath $Template.DetectionScriptPath

    $body = [ordered]@{
        publisher                   = $Template.Publisher
        displayName                 = $DisplayName
        description                 = $Description
        detectionScriptContent      = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionScriptContent))
        runAs32Bit                  = $Template.RunAs32Bit
        runAsAccount                = $Template.RunAsAccount
        enforceSignatureCheck       = $false
        roleScopeTagIds             = @('0')
        detectionScriptParameters   = @()
        remediationScriptParameters = @()
    }

    if (-not [string]::IsNullOrWhiteSpace($Template.RemediationScriptPath)) {
        $remediationScriptContent = Get-Content -LiteralPath $Template.RemediationScriptPath -Raw -Encoding utf8
        $body['remediationScriptContent'] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remediationScriptContent))
        $null = Save-HydrationGeneratedScript -RelativePath "Remediations/$($Template.TemplateId)/$([System.IO.Path]::GetFileName($Template.RemediationScriptPath))" -SourcePath $Template.RemediationScriptPath
    }

    if ($IncludeCreateOnlyProperties) {
        $body['@odata.type'] = '#microsoft.graph.deviceHealthScript'
        $body['isGlobalScript'] = $false
    }

    return $body
}
