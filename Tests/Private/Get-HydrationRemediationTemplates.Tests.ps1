#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Utilities/Resolve-HydrationTemplateChildPath.ps1
    . $PSScriptRoot/../../Private/Remediations/Get-HydrationRemediationTemplates.ps1
}

Describe 'Get-HydrationRemediationTemplates' {
    BeforeEach {
        $script:templateRoot = Join-Path TestDrive: 'Remediations'
        if (Test-Path -LiteralPath $script:templateRoot) {
            Remove-Item -LiteralPath $script:templateRoot -Recurse -Force
        }
        New-Item -Path $script:templateRoot -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path TestDrive: 'outside.ps1') -Value 'Write-Output outside' -Encoding utf8
    }

    It 'Rejects a detection script path that escapes its template directory' {
        @'
{
  "templateId": "traversal-test",
  "displayName": "Traversal Test",
  "publisher": "Test",
  "description": "Test",
  "runAsAccount": "system",
  "runAs32Bit": false,
  "detectionScript": "../outside.ps1"
}
'@ | Set-Content -LiteralPath (Join-Path $script:templateRoot 'metadata.json') -Encoding utf8

        { Get-HydrationRemediationTemplates -TemplatePath $script:templateRoot } | Should -Throw '*resolves outside template root*'
    }

    It 'Rejects a remediation script path that escapes its template directory' {
        Set-Content -LiteralPath (Join-Path $script:templateRoot 'detect.ps1') -Value 'exit 0' -Encoding utf8
        @'
{
  "templateId": "traversal-test",
  "displayName": "Traversal Test",
  "publisher": "Test",
  "description": "Test",
  "runAsAccount": "system",
  "runAs32Bit": false,
  "detectionScript": "detect.ps1",
  "remediationScript": "../outside.ps1"
}
'@ | Set-Content -LiteralPath (Join-Path $script:templateRoot 'metadata.json') -Encoding utf8

        { Get-HydrationRemediationTemplates -TemplatePath $script:templateRoot } | Should -Throw '*resolves outside template root*'
    }

    It 'Rejects duplicate template IDs before synchronization can become ambiguous' {
        foreach ($directoryName in @('First', 'Second')) {
            $templateDirectory = Join-Path $script:templateRoot $directoryName
            New-Item -Path $templateDirectory -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $templateDirectory 'detect.ps1') -Value 'exit 0' -Encoding utf8
            @"
{
  "templateId": "duplicate-template",
  "displayName": "$directoryName",
  "publisher": "Test",
  "description": "Test",
  "runAsAccount": "system",
  "runAs32Bit": false,
  "detectionScript": "detect.ps1"
}
"@ | Set-Content -LiteralPath (Join-Path $templateDirectory 'metadata.json') -Encoding utf8
        }

        { Get-HydrationRemediationTemplates -TemplatePath $script:templateRoot } | Should -Throw '*duplicate templateId*'
    }

    It 'Rejects duplicate display names before they collide in Intune' {
        foreach ($directoryName in @('First', 'Second')) {
            $templateDirectory = Join-Path $script:templateRoot $directoryName
            New-Item -Path $templateDirectory -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $templateDirectory 'detect.ps1') -Value 'exit 0' -Encoding utf8
            @"
{
  "templateId": "$directoryName-template",
  "displayName": "Duplicate Display Name",
  "publisher": "Test",
  "description": "Test",
  "runAsAccount": "system",
  "runAs32Bit": false,
  "detectionScript": "detect.ps1"
}
"@ | Set-Content -LiteralPath (Join-Path $templateDirectory 'metadata.json') -Encoding utf8
        }

        { Get-HydrationRemediationTemplates -TemplatePath $script:templateRoot } | Should -Throw '*duplicate displayName*'
    }

    It 'Rejects a string runAs32Bit value instead of coercing it to true' {
        Set-Content -LiteralPath (Join-Path $script:templateRoot 'detect.ps1') -Value 'exit 0' -Encoding utf8
        @'
{
  "templateId": "string-boolean-test",
  "displayName": "String Boolean Test",
  "publisher": "Test",
  "description": "Test",
  "runAsAccount": "system",
  "runAs32Bit": "false",
  "detectionScript": "detect.ps1"
}
'@ | Set-Content -LiteralPath (Join-Path $script:templateRoot 'metadata.json') -Encoding utf8

        { Get-HydrationRemediationTemplates -TemplatePath $script:templateRoot } | Should -Throw '*non-Boolean runAs32Bit*'
    }

    It 'Loads the bundled remediation catalog with parseable scripts' {
        $catalogPath = Join-Path $PSScriptRoot '../../Templates/Remediations'
        $templates = Get-HydrationRemediationTemplates -TemplatePath $catalogPath

        $templates | Should -HaveCount 6
        $templates.TemplateId | Should -Be @(
            'windows-disk-pressure-cleanup',
            'windows-device-health-reporting',
            'windows-automatic-time-zone',
            'windows-bitlocker-recovery-key-escrow',
            'windows-defender-signature-freshness',
            'windows-recovery-environment-health'
        )

        foreach ($scriptPath in @($templates.DetectionScriptPath) + @($templates.RemediationScriptPath | Where-Object { $_ })) {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty -Because $scriptPath
        }
    }
}
