function ConvertTo-IntuneWinRequirementRule {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Rule,

        [Parameter()]
        [string]$ScriptRootPath
    )

    $ruleType = [string]($Rule.RequirementType ?? $Rule.Type)
    switch ($ruleType) {
        'Registry' {
            return @{
                '@odata.type'        = '#microsoft.graph.win32LobAppRegistryRequirement'
                operator             = ($Rule.Operator ?? 'greaterThanOrEqual')
                detectionValue       = ($Rule.Value ?? '')
                keyPath              = $Rule.KeyPath
                valueName            = $Rule.ValueName
                check32BitOn64System = ConvertTo-HydrationBoolValue -Value ($Rule.Check32BitOn64System ?? $Rule.check32BitOn64System)
                operationType        = ($Rule.OperationType ?? $Rule.DetectionMethod ?? 'version')
            }
        }
        'File' {
            $operationType = ($Rule.OperationType ?? $Rule.DetectionMethod ?? 'version')
            return @{
                '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemRequirement'
                operator             = ($Rule.Operator ?? 'greaterThanOrEqual')
                detectionValue       = ($Rule.VersionValue ?? $Rule.Value ?? '')
                path                 = $Rule.Path
                fileOrFolderName     = ($Rule.FileOrFolderName ?? $Rule.FileOrFolder)
                check32BitOn64System = ConvertTo-HydrationBoolValue -Value ($Rule.Check32BitOn64System ?? $Rule.check32BitOn64System)
                operationType        = $operationType
            }
        }
        'Script' {
            $scriptFile = [string]$Rule.ScriptFile
            if ([string]::IsNullOrWhiteSpace($ScriptRootPath)) {
                throw "ScriptRootPath is required for script requirement rule '$scriptFile'."
            }

            $scriptPath = Join-Path -Path $ScriptRootPath -ChildPath $scriptFile
            $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
            $encodedScriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent))
            $scriptRule = @{
                '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptRequirement'
                operator              = ($Rule.Operator ?? 'greaterThanOrEqual')
                detectionValue        = ($Rule.Value ?? '')
                scriptContent         = $encodedScriptContent
                enforceSignatureCheck = ConvertTo-HydrationBoolValue -Value $Rule.EnforceSignatureCheck
                runAs32Bit            = ConvertTo-HydrationBoolValue -Value $Rule.RunAs32Bit
            }

            if ($Rule.RunAsAccount) {
                $scriptRule.runAsAccount = $Rule.RunAsAccount
            }

            return $scriptRule
        }
        'MSI' {
            return @{
                '@odata.type'  = '#microsoft.graph.win32LobAppProductCodeRequirement'
                operator       = ($Rule.Operator ?? 'greaterThanOrEqual')
                detectionValue = ($Rule.ProductVersion ?? $Rule.Value ?? '')
                productCode    = $Rule.ProductCode
                productVersion = ($Rule.ProductVersion ?? $Rule.Value ?? '')
            }
        }
        default {
            throw "Unsupported requirement rule type '$ruleType'."
        }
    }
}
