function Import-IntuneCustomCompliancePolicy {
    <#
    .SYNOPSIS
        Imports a single custom compliance policy that requires a compliance script.
    .DESCRIPTION
        Handles the sequential workflow for custom compliance policies:
        creates or reuses a compliance script, encodes rules to base64, then
        creates the policy. Returns a HydrationResult.
    .PARAMETER PolicyInfo
        Hashtable containing Name, Path, Endpoint, ImportBody, and Template.
    .PARAMETER ExistingComplianceScripts
        Hashtable of existing compliance scripts keyed by displayName.
    .OUTPUTS
        PSCustomObject (HydrationResult)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$PolicyInfo,

        [Parameter(Mandatory)]
        [hashtable]$ExistingComplianceScripts
    )

    $displayName = $PolicyInfo.Name
    $templateFile = @{ FullName = $PolicyInfo.Path }
    $importBody = $PolicyInfo.ImportBody
    $template = $PolicyInfo.Template
    $endpoint = "beta/$($PolicyInfo.Endpoint)"

    try {
        $scriptDefinition = $template.deviceCompliancePolicyScriptDefinition
        $scriptDisplayName = if ($scriptDefinition.displayName) { $scriptDefinition.displayName } else { "$displayName Script" }

        # Step 1: Check if compliance script already exists or create it
        $scriptId = $null
        if ($ExistingComplianceScripts.ContainsKey($scriptDisplayName)) {
            $scriptId = $ExistingComplianceScripts[$scriptDisplayName]
        } elseif ($scriptDefinition -and $scriptDefinition.detectionScriptContentBase64) {
            $scriptBody = @{
                description            = if ($scriptDefinition.description) { $scriptDefinition.description } else { "" }
                detectionScriptContent = $scriptDefinition.detectionScriptContentBase64
                displayName            = $scriptDisplayName
                enforceSignatureCheck  = [bool]$scriptDefinition.enforceSignatureCheck
                publisher              = if ($scriptDefinition.publisher) { $scriptDefinition.publisher } else { "Publisher" }
                runAs32Bit             = [bool]$scriptDefinition.runAs32Bit
                runAsAccount           = if ($scriptDefinition.runAsAccount) { $scriptDefinition.runAsAccount } else { "system" }
            }

            $newScript = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceComplianceScripts" -Body ($scriptBody | ConvertTo-Json -Depth 10) -ContentType "application/json" -ErrorAction Stop
            $scriptId = $newScript.id
            $ExistingComplianceScripts[$scriptDisplayName] = $scriptId
        } else {
            Write-Warning "Skipping compliance policy '$displayName' - no script definition found with detectionScriptContentBase64"
            return New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing detectionScriptContentBase64 in deviceCompliancePolicyScriptDefinition'
        }

        # Step 2: Convert rules to base64
        $rulesSource = $scriptDefinition.rules
        if (-not $rulesSource) {
            Write-Warning "Skipping compliance policy '$displayName' - no rules found in deviceCompliancePolicyScriptDefinition"
            return New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing rules in deviceCompliancePolicyScriptDefinition'
        }

        $rulesJson = $rulesSource | ConvertTo-Json -Depth 100 -Compress
        $rulesBytes = [System.Text.Encoding]::UTF8.GetBytes($rulesJson)
        $rulesBase64 = [System.Convert]::ToBase64String($rulesBytes)

        # Step 3: Update the policy body with resolved values
        $importBody.deviceCompliancePolicyScript = @{
            deviceComplianceScriptId = $scriptId
            rulesContent             = $rulesBase64
        }

        # Remove internal helper definition before sending
        if ($importBody.PSObject.Properties['deviceCompliancePolicyScriptDefinition']) {
            $null = $importBody.PSObject.Properties.Remove('deviceCompliancePolicyScriptDefinition')
        }

        $null = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType "application/json" -ErrorAction Stop
        Write-HydrationLog -Message "  Created: $displayName" -Level Info
        return New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Created' -Status 'Success'
    } catch {
        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
        Write-HydrationLog -Message "  Failed: $displayName - $errMessage" -Level Warning
        return New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status $errMessage
    }
}
