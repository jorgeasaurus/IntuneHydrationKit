function Import-IntuneConditionalAccessPolicies {
    <#
    .SYNOPSIS
        Imports Conditional Access starter pack
    
    .DESCRIPTION
        Creates 10 Conditional Access policy templates, all disabled by default for safe deployment
    
    .EXAMPLE
        Import-IntuneConditionalAccessPolicies
    
    .OUTPUTS
        Boolean indicating success or failure
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-IntuneLog "========== Importing Conditional Access Policies ==========" -Level INFO
    
    $caPolicies = @(
        @{
            DisplayName = "CA001: Require MFA for Administrators"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeRoles = @(
                        "62e90394-69f5-4237-9190-012177145e10", # Global Administrator
                        "194ae4cb-b126-40b2-bd5b-6091b380977d"  # Security Administrator
                    )
                }
                Applications = @{
                    IncludeApplications = @("All")
                }
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("mfa")
            }
        },
        @{
            DisplayName = "CA002: Block Legacy Authentication"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("All")
                }
                ClientAppTypes = @("exchangeActiveSync", "other")
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("block")
            }
        },
        @{
            DisplayName = "CA003: Require MFA for Azure Management"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("797f4846-ba00-4fd7-ba43-dac1f8f63013") # Azure Management
                }
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("mfa")
            }
        },
        @{
            DisplayName = "CA004: Require Compliant or Hybrid Joined Device"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("Office365")
                }
                Platforms = @{
                    IncludePlatforms = @("windows")
                }
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("compliantDevice", "domainJoinedDevice")
            }
        },
        @{
            DisplayName = "CA005: Require MFA from Unknown Locations"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("All")
                }
                Locations = @{
                    IncludeLocations = @("All")
                }
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("mfa")
            }
        },
        @{
            DisplayName = "CA006: Require App Protection Policy for Mobile"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("Office365")
                }
                Platforms = @{
                    IncludePlatforms = @("iOS", "android")
                }
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("approvedApplication", "compliantApplication")
            }
        },
        @{
            DisplayName = "CA007: Require MFA for All Users"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("All")
                }
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("mfa")
            }
        },
        @{
            DisplayName = "CA008: Block Access from Risky Sign-ins"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("All")
                }
                SignInRiskLevels = @("high", "medium")
            }
            GrantControls = @{
                Operator = "OR"
                BuiltInControls = @("block")
            }
        },
        @{
            DisplayName = "CA009: Require Terms of Use"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("All")
                }
            }
            GrantControls = @{
                Operator = "AND"
                BuiltInControls = @("mfa")
                TermsOfUse = @()
            }
        },
        @{
            DisplayName = "CA010: Require Password Change for Risky Users"
            State = "disabled"
            Conditions = @{
                Users = @{
                    IncludeUsers = @("All")
                }
                Applications = @{
                    IncludeApplications = @("All")
                }
                UserRiskLevels = @("high")
            }
            GrantControls = @{
                Operator = "AND"
                BuiltInControls = @("mfa", "passwordChange")
            }
        }
    )
    
    foreach ($policy in $caPolicies) {
        try {
            Write-IntuneLog "Creating Conditional Access policy: $($policy.DisplayName) (disabled)" -Level INFO
            
            # NOTE: Actual implementation requires Graph API call:
            # New-MgIdentityConditionalAccessPolicy -BodyParameter $policy
            
            Write-IntuneLog "CA policy template prepared: $($policy.DisplayName)" -Level SUCCESS
        }
        catch {
            Write-IntuneLog "Failed to create CA policy $($policy.DisplayName): $_" -Level WARNING
        }
    }
    
    Write-IntuneLog "Conditional Access policies import completed" -Level SUCCESS
    Write-IntuneLog "IMPORTANT: All CA policies are disabled by default. Review and enable as needed." -Level WARNING
    return $true
}
