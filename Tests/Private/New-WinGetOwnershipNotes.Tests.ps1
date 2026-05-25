#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/New-WinGetOwnershipNotes.ps1
}

Describe 'New-WinGetOwnershipNotes' {
    It 'Should remove duplicate note lines while preserving first-seen order' {
        $template = [pscustomobject]@{
            templateId = 'contoso-app'
            metadata   = [pscustomobject]@{
                notes        = @(
                    'Keep first',
                    'Imported from WinGet',
                    'Keep first'
                )
                placeholders = [pscustomobject]@{
                    customNotes = @(
                        'Custom note',
                        'Imported from WinGet',
                        'Custom note'
                    )
                }
                markers      = [pscustomobject]@{
                    source = 'Imported from WinGet'
                }
            }
        }
        $packageMetadata = [pscustomobject]@{
            PackageIdentifier = 'Contoso.App'
            PackageVersion    = '1.0.0'
            ManifestSource    = [pscustomobject]@{
                Repository = 'winget-pkgs'
            }
            ManifestPath      = 'manifests/c/Contoso/App/1.0.0'
        }

        $result = New-WinGetOwnershipNotes -Template $template -PackageMetadata $packageMetadata

        $result -split [Environment]::NewLine | Should -Be @(
            'Keep first',
            'Imported from WinGet',
            'Custom note',
            'WinGetPackageIdentifier: Contoso.App',
            'WinGetPackageVersion: 1.0.0',
            'WinGetTemplateId: contoso-app',
            'WinGetManifestRepository: winget-pkgs',
            'WinGetManifestPath: manifests/c/Contoso/App/1.0.0'
        )
    }
}
