#Requires -Modules Pester

BeforeAll {
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Remove-ReadOnlyGraphProperties.ps1'
    . $functionPath
}

Describe 'Remove-ReadOnlyGraphProperties' {
    Context 'Core read-only properties' {
        It 'Should remove id property' {
            $obj = [PSCustomObject]@{ id = 'abc-123'; displayName = 'Test' }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.PSObject.Properties['id'] | Should -BeNullOrEmpty
        }

        It 'Should remove createdDateTime property' {
            $obj = [PSCustomObject]@{ createdDateTime = '2024-01-01'; displayName = 'Test' }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.PSObject.Properties['createdDateTime'] | Should -BeNullOrEmpty
        }

        It 'Should remove lastModifiedDateTime property' {
            $obj = [PSCustomObject]@{ lastModifiedDateTime = '2024-01-01'; displayName = 'Test' }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.PSObject.Properties['lastModifiedDateTime'] | Should -BeNullOrEmpty
        }

        It 'Should remove version property' {
            $obj = [PSCustomObject]@{ version = '1'; displayName = 'Test' }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.PSObject.Properties['version'] | Should -BeNullOrEmpty
        }

        It 'Should remove @odata.context property' {
            $obj = [PSCustomObject]@{ '@odata.context' = 'https://graph.microsoft.com'; displayName = 'Test' }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.PSObject.Properties['@odata.context'] | Should -BeNullOrEmpty
        }

        It 'Should remove all core read-only properties at once' {
            $obj = [PSCustomObject]@{
                id                   = 'abc-123'
                createdDateTime      = '2024-01-01'
                lastModifiedDateTime = '2024-06-01'
                version              = '3'
                '@odata.context'     = 'https://graph.microsoft.com'
                displayName          = 'Keep This'
                description          = 'Also keep'
            }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.PSObject.Properties['id'] | Should -BeNullOrEmpty
            $obj.PSObject.Properties['createdDateTime'] | Should -BeNullOrEmpty
            $obj.PSObject.Properties['lastModifiedDateTime'] | Should -BeNullOrEmpty
            $obj.PSObject.Properties['version'] | Should -BeNullOrEmpty
            $obj.PSObject.Properties['@odata.context'] | Should -BeNullOrEmpty
        }
    }

    Context 'Preserving non-read-only properties' {
        It 'Should preserve displayName and description' {
            $obj = [PSCustomObject]@{
                id          = 'abc-123'
                displayName = 'My Policy'
                description = 'Important policy'
            }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.displayName | Should -Be 'My Policy'
            $obj.description | Should -Be 'Important policy'
        }

        It 'Should preserve custom properties' {
            $obj = [PSCustomObject]@{
                id         = 'abc-123'
                customProp = 'value'
                '@odata.type' = '#microsoft.graph.policy'
            }
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj.customProp | Should -Be 'value'
            $obj.'@odata.type' | Should -Be '#microsoft.graph.policy'
        }
    }

    Context 'AdditionalProperties parameter' {
        It 'Should remove additional specified properties' {
            $obj = [PSCustomObject]@{
                id               = 'abc-123'
                displayName      = 'Test'
                roleScopeTagIds  = @('0')
                settingCount     = 5
            }
            Remove-ReadOnlyGraphProperties -InputObject $obj -AdditionalProperties @('roleScopeTagIds', 'settingCount')
            $obj.PSObject.Properties['roleScopeTagIds'] | Should -BeNullOrEmpty
            $obj.PSObject.Properties['settingCount'] | Should -BeNullOrEmpty
            $obj.displayName | Should -Be 'Test'
        }

        It 'Should remove both core and additional properties' {
            $obj = [PSCustomObject]@{
                id          = 'abc-123'
                displayName = 'Test'
                customField = 'remove me'
            }
            Remove-ReadOnlyGraphProperties -InputObject $obj -AdditionalProperties @('customField')
            $obj.PSObject.Properties['id'] | Should -BeNullOrEmpty
            $obj.PSObject.Properties['customField'] | Should -BeNullOrEmpty
            $obj.displayName | Should -Be 'Test'
        }
    }

    Context 'Properties that do not exist' {
        It 'Should not error when properties are missing from object' {
            $obj = [PSCustomObject]@{ displayName = 'Test' }
            { Remove-ReadOnlyGraphProperties -InputObject $obj } | Should -Not -Throw
        }

        It 'Should not error when additional properties are missing' {
            $obj = [PSCustomObject]@{ displayName = 'Test' }
            { Remove-ReadOnlyGraphProperties -InputObject $obj -AdditionalProperties @('nonExistent') } | Should -Not -Throw
        }
    }

    Context 'In-place modification' {
        It 'Should modify the original object (not return a copy)' {
            $obj = [PSCustomObject]@{ id = 'abc-123'; displayName = 'Test' }
            $originalRef = $obj
            Remove-ReadOnlyGraphProperties -InputObject $obj
            $obj | Should -Be $originalRef
            $obj.PSObject.Properties['id'] | Should -BeNullOrEmpty
        }
    }
}
