function ConvertTo-IntuneWinDetectionRule {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Rule,

        [Parameter()]
        [string]$ScriptRootPath
    )

    $ruleType = [string]($Rule.DetectionType ?? $Rule.Type)
    switch ($ruleType) {
        'MSI' {
            return @{
                '@odata.type'          = '#microsoft.graph.win32LobAppProductCodeRule'
                ruleType               = 'detection'
                productCode            = $Rule.ProductCode
                productVersionOperator = ($Rule.ProductVersionOperator ?? 'notConfigured')
                productVersion         = ($Rule.ProductVersion ?? '')
            }
        }
        'Registry' {
            $operationSource = [string]($Rule.RegistryDetectionType ?? $Rule.DetectionMethod ?? $Rule.DetectionType ?? 'existence')
            $normalizedOperation = $operationSource.ToLowerInvariant()
            $registryRule = @{
                '@odata.type'        = '#microsoft.graph.win32LobAppRegistryRule'
                ruleType             = 'detection'
                keyPath              = $Rule.KeyPath
                valueName            = $Rule.ValueName
                check32BitOn64System = ConvertTo-HydrationBoolValue -Value ($Rule.Check32BitOn64System ?? $Rule.check32BitOn64System)
            }

            switch ($normalizedOperation) {
                { $_ -in @('existence', 'exists') } {
                    $registryRule.operationType = 'exists'
                    $registryRule.operator = 'notConfigured'
                    break
                }
                { $_ -in @('notexists', 'doesnotexist') } {
                    $registryRule.operationType = 'doesNotExist'
                    $registryRule.operator = 'notConfigured'
                    break
                }
                { $_ -in @('versioncomparison', 'version') } {
                    $registryRule.operationType = 'version'
                    $registryRule.operator = ($Rule.Operator ?? 'greaterThanOrEqual')
                    $registryRule.comparisonValue = ($Rule.Value ?? '')
                    break
                }
                { $_ -in @('stringcomparison', 'string') } {
                    $registryRule.operationType = 'string'
                    $registryRule.operator = ($Rule.Operator ?? 'equal')
                    $registryRule.comparisonValue = ($Rule.Value ?? '')
                    break
                }
                { $_ -in @('integercomparison', 'integer') } {
                    $registryRule.operationType = 'integer'
                    $registryRule.operator = ($Rule.Operator ?? 'greaterThanOrEqual')
                    $registryRule.comparisonValue = ($Rule.Value ?? '')
                    break
                }
                default {
                    throw "Unsupported registry detection method '$operationSource'."
                }
            }

            return $registryRule
        }
        'File' {
            $operationSource = [string]($Rule.FileDetectionType ?? $Rule.DetectionMethod ?? $Rule.DetectionType ?? 'exists')
            $normalizedOperation = $operationSource.ToLowerInvariant()
            $fileRule = @{
                '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemRule'
                ruleType             = 'detection'
                path                 = $Rule.Path
                fileOrFolderName     = ($Rule.FileOrFolderName ?? $Rule.FileOrFolder)
                check32BitOn64System = ConvertTo-HydrationBoolValue -Value ($Rule.Check32BitOn64System ?? $Rule.check32BitOn64System)
            }

            switch ($normalizedOperation) {
                { $_ -in @('exists', 'existence') } {
                    $fileRule.operationType = 'exists'
                    $fileRule.operator = 'notConfigured'
                    break
                }
                { $_ -in @('notexists', 'doesnotexist') } {
                    $fileRule.operationType = 'doesNotExist'
                    $fileRule.operator = 'notConfigured'
                    break
                }
                { $_ -in @('versioncomparison', 'version') } {
                    $fileRule.operationType = 'version'
                    $fileRule.operator = ($Rule.Operator ?? 'greaterThanOrEqual')
                    $fileRule.comparisonValue = ($Rule.VersionValue ?? $Rule.Value ?? '')
                    break
                }
                { $_ -in @('stringcomparison', 'string') } {
                    $fileRule.operationType = 'string'
                    $fileRule.operator = ($Rule.Operator ?? 'equal')
                    $fileRule.comparisonValue = ($Rule.Value ?? '')
                    break
                }
                { $_ -in @('integercomparison', 'integer', 'sizeinmb', 'size') } {
                    $fileRule.operationType = 'sizeInMB'
                    $fileRule.operator = ($Rule.Operator ?? 'greaterThanOrEqual')
                    $fileRule.comparisonValue = ($Rule.Value ?? '')
                    break
                }
                default {
                    throw "Unsupported file detection method '$operationSource'."
                }
            }

            return $fileRule
        }
        'Script' {
            $scriptFile = [string]$Rule.ScriptFile
            if ([string]::IsNullOrWhiteSpace($ScriptRootPath)) {
                throw "ScriptRootPath is required for script detection rule '$scriptFile'."
            }

            $scriptPath = Join-Path -Path $ScriptRootPath -ChildPath $scriptFile
            $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
            $encodedScriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent))
            $scriptRule = @{
                '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptRule'
                ruleType              = 'detection'
                scriptContent         = $encodedScriptContent
                enforceSignatureCheck = ConvertTo-HydrationBoolValue -Value $Rule.EnforceSignatureCheck
                runAs32Bit            = ConvertTo-HydrationBoolValue -Value $Rule.RunAs32Bit
            }

            if ($Rule.OperationType) {
                $scriptRule.operationType = $Rule.OperationType
            }

            if ($Rule.Operator) {
                $scriptRule.operator = $Rule.Operator
            }

            if ($null -ne $Rule.ComparisonValue) {
                $scriptRule.comparisonValue = $Rule.ComparisonValue
            }

            return $scriptRule
        }
        default {
            throw "Unsupported detection rule type '$ruleType'."
        }
    }
}
