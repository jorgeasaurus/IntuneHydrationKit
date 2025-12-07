#Requires -Modules Pester

BeforeAll {
    # Import the function under test
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Test-WindowsDriverUpdateLicense.ps1'
    . $functionPath
}

Describe 'Test-WindowsDriverUpdateLicense' {
    BeforeEach {
        # Reset mock state before each test
        Mock -CommandName Invoke-MgGraphRequest -MockWith { }
    }

    Context 'When tenant has Windows Enterprise E3 license' {
        It 'Should return $true when WIN10_PRO_ENT_SUB service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'ENTERPRISEPACK'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'WIN10_PRO_ENT_SUB'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }

    Context 'When tenant has Microsoft 365 E3 license' {
        It 'Should return $true when SPE_E3 service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E3'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }

        It 'Should return $true when M365_E5 service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E5'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'M365_E5'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }

    Context 'When tenant has Microsoft 365 Business Premium license' {
        It 'Should return $true when SPB service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'O365_BUSINESS_PREMIUM'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPB'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }

    Context 'When tenant has Education licenses' {
        It 'Should return $true when M365EDU_A3_FACULTY service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'M365EDU_A3_FACULTY'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'M365EDU_A3_FACULTY'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }

    Context 'When tenant has Windows 365 Enterprise license' {
        It 'Should return $true when Windows 365 Enterprise service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'CPC_E_2C_8GB_128GB'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'CPC_E_2C_8GB_128GB'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }

    Context 'When tenant has no compatible license' {
        It 'Should return $false when no matching service plans are found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'EXCHANGESTANDARD'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'EXCHANGE_S_STANDARD'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $false
        }

        It 'Should return $false when tenant has no SKUs' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @()
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $false
        }
    }

    Context 'When SKU is disabled' {
        It 'Should skip disabled SKUs and return $false' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E3'
                            capabilityStatus = 'Suspended'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $false
        }

        It 'Should return $true when there is both disabled and enabled SKU with valid license' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E3'
                            capabilityStatus = 'Suspended'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3'
                                    provisioningStatus = 'Success'
                                }
                            )
                        },
                        @{
                            skuPartNumber = 'SPE_E5'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E5'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }

    Context 'When service plan provisioning status is not Success' {
        It 'Should return $false when service plan provisioningStatus is PendingInput' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E3'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3'
                                    provisioningStatus = 'PendingInput'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $false
        }

        It 'Should return $false when service plan provisioningStatus is Disabled' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E3'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3'
                                    provisioningStatus = 'Disabled'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $false
        }
    }

    Context 'When Graph API call fails' {
        It 'Should return $true and write warning on API error' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                throw 'Authentication error'
            }
            Mock -CommandName Write-Warning -MockWith { }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
            Should -Invoke -CommandName Write-Warning -Times 1
        }
    }

    Context 'When multiple SKUs contain mixed valid and invalid licenses' {
        It 'Should return $true when at least one valid license exists' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'EXCHANGESTANDARD'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'EXCHANGE_S_STANDARD'
                                    provisioningStatus = 'Success'
                                }
                            )
                        },
                        @{
                            skuPartNumber = 'FLOW_FREE'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'FLOW_P2_VIRAL'
                                    provisioningStatus = 'Success'
                                }
                            )
                        },
                        @{
                            skuPartNumber = 'SPE_E3'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3'
                                    provisioningStatus = 'Success'
                                },
                                @{
                                    servicePlanName = 'EXCHANGE_S_ENTERPRISE'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }

    Context 'Verbose output' {
        It 'Should write verbose message when compatible license is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E3'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }
            Mock -CommandName Write-Verbose -MockWith { }

            Test-WindowsDriverUpdateLicense -Verbose
            Should -Invoke -CommandName Write-Verbose -Times 1 -ParameterFilter {
                $Message -like '*Windows Driver Update compatible license*'
            }
        }

        It 'Should write verbose message when no compatible license is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'EXCHANGESTANDARD'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'EXCHANGE_S_STANDARD'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }
            Mock -CommandName Write-Verbose -MockWith { }

            Test-WindowsDriverUpdateLicense -Verbose
            Should -Invoke -CommandName Write-Verbose -Times 1 -ParameterFilter {
                $Message -like '*No Windows Driver Update compatible license*'
            }
        }
    }

    Context 'Government and GCC High licenses' {
        It 'Should return $true when SPE_E3_GOV service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E3_GOV'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E3_GOV'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }

        It 'Should return $true when SPE_E5_USGOV_GCCHIGH service plan is found' {
            Mock -CommandName Invoke-MgGraphRequest -MockWith {
                @{
                    value = @(
                        @{
                            skuPartNumber = 'SPE_E5_USGOV_GCCHIGH'
                            capabilityStatus = 'Enabled'
                            servicePlans = @(
                                @{
                                    servicePlanName = 'SPE_E5_USGOV_GCCHIGH'
                                    provisioningStatus = 'Success'
                                }
                            )
                        }
                    )
                }
            }

            $result = Test-WindowsDriverUpdateLicense
            $result | Should -Be $true
        }
    }
}
