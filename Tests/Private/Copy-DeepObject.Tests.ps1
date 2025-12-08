#Requires -Modules Pester

BeforeAll {
    # Import the function under test
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Copy-DeepObject.ps1'
    . $functionPath
}

Describe 'Copy-DeepObject' {
    Context 'When copying simple objects' {
        It 'Should create a copy of a hashtable' {
            $original = @{
                Name  = 'Test'
                Value = 123
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy | Should -Not -BeNullOrEmpty
            $copy.Name | Should -Be 'Test'
            $copy.Value | Should -Be 123
        }

        It 'Should create an independent copy (modifying copy does not affect original)' {
            $original = @{
                Name = 'Original'
            }

            $copy = Copy-DeepObject -InputObject $original
            $copy.Name = 'Modified'

            $original.Name | Should -Be 'Original'
            $copy.Name | Should -Be 'Modified'
        }

        It 'Should copy a string' {
            $original = 'TestString'

            $copy = Copy-DeepObject -InputObject $original

            $copy | Should -Be 'TestString'
        }

        It 'Should copy an integer' {
            $original = 42

            $copy = Copy-DeepObject -InputObject $original

            $copy | Should -Be 42
        }

        It 'Should copy a boolean' {
            $original = $true

            $copy = Copy-DeepObject -InputObject $original

            $copy | Should -Be $true
        }
    }

    Context 'When copying arrays' {
        It 'Should create a copy of a simple array' {
            $original = @(1, 2, 3, 4, 5)

            $copy = Copy-DeepObject -InputObject $original

            $copy | Should -HaveCount 5
            $copy[0] | Should -Be 1
            $copy[4] | Should -Be 5
        }

        It 'Should create an independent copy of an array' {
            $original = @(1, 2, 3)

            $copy = Copy-DeepObject -InputObject $original
            $copy[0] = 99

            $original[0] | Should -Be 1
            $copy[0] | Should -Be 99
        }

        It 'Should copy an array of strings' {
            $original = @('apple', 'banana', 'cherry')

            $copy = Copy-DeepObject -InputObject $original

            $copy | Should -HaveCount 3
            $copy | Should -Contain 'apple'
            $copy | Should -Contain 'banana'
            $copy | Should -Contain 'cherry'
        }
    }

    Context 'When copying nested objects' {
        It 'Should deep copy nested hashtables' {
            $original = @{
                Level1 = @{
                    Level2 = @{
                        Value = 'DeepValue'
                    }
                }
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy.Level1.Level2.Value | Should -Be 'DeepValue'
        }

        It 'Should create independent nested copies' {
            $original = @{
                Nested = @{
                    Value = 'Original'
                }
            }

            $copy = Copy-DeepObject -InputObject $original
            $copy.Nested.Value = 'Modified'

            $original.Nested.Value | Should -Be 'Original'
            $copy.Nested.Value | Should -Be 'Modified'
        }

        It 'Should deep copy hashtables containing arrays' {
            $original = @{
                Items = @(1, 2, 3)
                Name  = 'Test'
            }

            $copy = Copy-DeepObject -InputObject $original
            $copy.Items[0] = 99

            $original.Items[0] | Should -Be 1
            $copy.Items[0] | Should -Be 99
        }

        It 'Should deep copy arrays containing hashtables' {
            $original = @(
                @{ Name = 'Item1'; Value = 1 },
                @{ Name = 'Item2'; Value = 2 }
            )

            $copy = Copy-DeepObject -InputObject $original
            $copy[0].Name = 'Modified'

            $original[0].Name | Should -Be 'Item1'
            $copy[0].Name | Should -Be 'Modified'
        }
    }

    Context 'When copying PSCustomObjects' {
        It 'Should copy a PSCustomObject' {
            $original = [PSCustomObject]@{
                Name    = 'TestObject'
                Id      = 123
                Enabled = $true
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy.Name | Should -Be 'TestObject'
            $copy.Id | Should -Be 123
            $copy.Enabled | Should -Be $true
        }

        It 'Should create an independent copy of PSCustomObject' {
            $original = [PSCustomObject]@{
                Name = 'Original'
            }

            $copy = Copy-DeepObject -InputObject $original
            $copy.Name = 'Modified'

            $original.Name | Should -Be 'Original'
            $copy.Name | Should -Be 'Modified'
        }

        It 'Should deep copy nested PSCustomObjects' {
            $original = [PSCustomObject]@{
                Outer = [PSCustomObject]@{
                    Inner = [PSCustomObject]@{
                        Value = 'DeepNested'
                    }
                }
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy.Outer.Inner.Value | Should -Be 'DeepNested'
        }
    }

    Context 'When copying complex real-world structures' {
        It 'Should copy a settings-like structure' {
            $original = @{
                tenant         = @{
                    tenantId   = '12345678-1234-1234-1234-123456789012'
                    tenantName = 'contoso.onmicrosoft.com'
                }
                authentication = @{
                    mode        = 'interactive'
                    environment = 'Global'
                }
                options        = @{
                    create  = $true
                    delete  = $false
                    dryRun  = $true
                    verbose = $false
                }
                imports        = @{
                    dynamicGroups     = $true
                    deviceFilters     = $true
                    conditionalAccess = $false
                }
            }

            $copy = Copy-DeepObject -InputObject $original
            $copy.options.create = $false
            $copy.imports.dynamicGroups = $false

            $original.options.create | Should -Be $true
            $original.imports.dynamicGroups | Should -Be $true
            $copy.options.create | Should -Be $false
            $copy.imports.dynamicGroups | Should -Be $false
        }

        It 'Should copy an Intune policy-like structure' {
            $original = @{
                displayName = 'Test Policy'
                description = 'Test Description'
                settings    = @(
                    @{
                        settingDefinitionId = 'setting1'
                        settingInstance     = @{
                            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                            choiceSettingValue = @{
                                value = 'enabled'
                            }
                        }
                    },
                    @{
                        settingDefinitionId = 'setting2'
                        settingInstance     = @{
                            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                            simpleSettingValue = @{
                                value = 100
                            }
                        }
                    }
                )
            }

            $copy = Copy-DeepObject -InputObject $original
            $copy.settings[0].settingInstance.choiceSettingValue.value = 'disabled'

            $original.settings[0].settingInstance.choiceSettingValue.value | Should -Be 'enabled'
            $copy.settings[0].settingInstance.choiceSettingValue.value | Should -Be 'disabled'
        }
    }

    Context 'When copying null and empty values' {
        It 'Should throw when null input is provided (Mandatory parameter)' {
            { Copy-DeepObject -InputObject $null } | Should -Throw
        }

        It 'Should copy an empty hashtable (serializes to null)' {
            $original = @{}

            $copy = Copy-DeepObject -InputObject $original

            # PSSerializer serializes empty hashtables to null
            $copy | Should -BeNullOrEmpty
        }

        It 'Should copy an empty array' {
            $original = @()

            $copy = Copy-DeepObject -InputObject $original

            $copy | Should -HaveCount 0
        }

        It 'Should preserve null values in hashtables' {
            $original = @{
                HasValue = 'something'
                IsNull   = $null
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy.HasValue | Should -Be 'something'
            $copy.IsNull | Should -BeNullOrEmpty
        }
    }

    Context 'When copying special types' {
        It 'Should copy DateTime objects' {
            $original = @{
                Created = [DateTime]::new(2024, 1, 15, 10, 30, 0)
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy.Created.Year | Should -Be 2024
            $copy.Created.Month | Should -Be 1
            $copy.Created.Day | Should -Be 15
        }

        It 'Should copy GUID values' {
            $guid = [Guid]::NewGuid()
            $original = @{
                Id = $guid
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy.Id | Should -Be $guid
        }

        It 'Should copy TimeSpan objects' {
            $original = @{
                Duration = [TimeSpan]::FromHours(2)
            }

            $copy = Copy-DeepObject -InputObject $original

            $copy.Duration.TotalHours | Should -Be 2
        }
    }

    Context 'Reference verification' {
        It 'Should not return the same reference for hashtables' {
            $original = @{ Key = 'Value' }

            $copy = Copy-DeepObject -InputObject $original

            [Object]::ReferenceEquals($original, $copy) | Should -Be $false
        }

        It 'Should not return the same reference for nested objects' {
            $original = @{
                Nested = @{ Key = 'Value' }
            }

            $copy = Copy-DeepObject -InputObject $original

            [Object]::ReferenceEquals($original.Nested, $copy.Nested) | Should -Be $false
        }

        It 'Should not return the same reference for arrays' {
            $original = @(1, 2, 3)

            $copy = Copy-DeepObject -InputObject $original

            [Object]::ReferenceEquals($original, $copy) | Should -Be $false
        }

        It 'Should not return the same reference for PSCustomObjects' {
            $original = [PSCustomObject]@{ Key = 'Value' }

            $copy = Copy-DeepObject -InputObject $original

            [Object]::ReferenceEquals($original, $copy) | Should -Be $false
        }
    }
}
