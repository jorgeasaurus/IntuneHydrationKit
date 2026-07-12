#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Utilities/Resolve-HydrationTemplateChildPath.ps1
}

Describe 'Resolve-HydrationTemplateChildPath' {
    BeforeAll {
        $script:artifactRoot = Join-Path $PSScriptRoot '../../build/PesterArtifacts/Resolve-HydrationTemplateChildPath'
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }

        $null = New-Item -Path $script:artifactRoot -ItemType Directory -Force
        'inside' | Set-Content -Path (Join-Path $script:artifactRoot 'inside.ps1')
        'outside' | Set-Content -Path (Join-Path $script:artifactRoot '../outside-child.ps1')
    }

    AfterAll {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
    }

    It 'Should resolve a child path under the template root' {
        $resolvedPath = Resolve-HydrationTemplateChildPath -RootPath $script:artifactRoot -ChildPath 'inside.ps1'

        $resolvedPath | Should -Be (Resolve-Path -LiteralPath (Join-Path $script:artifactRoot 'inside.ps1')).Path
    }

    It 'Should reject child traversal outside the template root' {
        {
            Resolve-HydrationTemplateChildPath -RootPath $script:artifactRoot -ChildPath '../outside-child.ps1' -PathLabel 'Script file'
        } | Should -Throw "*resolves outside template root*"
    }

    It 'Should reject case-only sibling traversal on case-sensitive platforms' -Skip:$IsWindows {
        Mock Resolve-Path {
            param([string]$LiteralPath)
            if ($LiteralPath -eq '/tmp/Scripts') {
                return [pscustomobject]@{ Path = '/tmp/Scripts' }
            }
            if ($LiteralPath -eq '/tmp/Scripts/../scripts/secret.ps1') {
                return [pscustomobject]@{ Path = '/tmp/scripts/secret.ps1' }
            }
            throw "Unexpected path: $LiteralPath"
        }

        {
            Resolve-HydrationTemplateChildPath -RootPath '/tmp/Scripts' -ChildPath '../scripts/secret.ps1' -PathLabel 'Script file'
        } | Should -Throw "*resolves outside template root*"
    }
}
