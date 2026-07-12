function New-WinGetRemediationBody {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Definition,

        [Parameter(Mandatory)]
        [bool]$IncludeCreateOnlyProperties
    )

    $detectionScriptContent = New-WinGetRemediationScriptContent -PackageIdentifiers $Definition.PackageIdentifiers -Scope $Definition.Scope -ScriptType 'Detection'
    $remediationScriptContent = New-WinGetRemediationScriptContent -PackageIdentifiers $Definition.PackageIdentifiers -Scope $Definition.Scope -ScriptType 'Remediation'
    $scopeFolderName = [cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($Definition.Scope)
    $null = Save-HydrationGeneratedScript -RelativePath "WinGetRemediations/$scopeFolderName/Detect-WinGetAppUpdates.ps1" -Content $detectionScriptContent
    $null = Save-HydrationGeneratedScript -RelativePath "WinGetRemediations/$scopeFolderName/Remediate-WinGetAppUpdates.ps1" -Content $remediationScriptContent

    $body = @{
        publisher                   = 'WinGet'
        displayName                 = $Definition.DisplayName
        description                 = $Definition.Description
        detectionScriptContent      = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionScriptContent))
        remediationScriptContent    = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remediationScriptContent))
        runAs32Bit                  = $false
        runAsAccount                = $Definition.RunAsAccount
        enforceSignatureCheck       = $false
        roleScopeTagIds             = @('0')
        detectionScriptParameters   = @()
        remediationScriptParameters = @()
    }

    if ($IncludeCreateOnlyProperties) {
        $body['@odata.type'] = '#microsoft.graph.deviceHealthScript'
        $body['isGlobalScript'] = $false
    }

    return $body
}
