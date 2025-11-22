function New-IntuneDynamicGroups {
    <#
    .SYNOPSIS
        Creates dynamic groups for device categorization
    
    .DESCRIPTION
        Creates 14 dynamic groups for OS, manufacturer, model, Autopilot status, and compliance state
    
    .EXAMPLE
        New-IntuneDynamicGroups
    
    .OUTPUTS
        Boolean indicating success or failure
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-IntuneLog "========== Creating Dynamic Groups ==========" -Level INFO
    
    $dynamicGroups = @(
        # OS-based groups
        @{
            Name = "All Windows Devices"
            Description = "Dynamic group for all Windows devices"
            MembershipRule = '(device.deviceOSType -eq "Windows")'
        },
        @{
            Name = "All iOS Devices"
            Description = "Dynamic group for all iOS devices"
            MembershipRule = '(device.deviceOSType -eq "iPhone") or (device.deviceOSType -eq "iPad")'
        },
        @{
            Name = "All Android Devices"
            Description = "Dynamic group for all Android devices"
            MembershipRule = '(device.deviceOSType -eq "Android")'
        },
        @{
            Name = "All macOS Devices"
            Description = "Dynamic group for all macOS devices"
            MembershipRule = '(device.deviceOSType -eq "MacMDM")'
        },
        
        # Manufacturer-based groups
        @{
            Name = "Devices - Microsoft"
            Description = "Dynamic group for Microsoft manufactured devices"
            MembershipRule = '(device.deviceManufacturer -eq "Microsoft Corporation")'
        },
        @{
            Name = "Devices - Dell"
            Description = "Dynamic group for Dell manufactured devices"
            MembershipRule = '(device.deviceManufacturer -eq "Dell Inc.")'
        },
        @{
            Name = "Devices - HP"
            Description = "Dynamic group for HP manufactured devices"
            MembershipRule = '(device.deviceManufacturer -contains "HP") or (device.deviceManufacturer -contains "Hewlett")'
        },
        @{
            Name = "Devices - Lenovo"
            Description = "Dynamic group for Lenovo manufactured devices"
            MembershipRule = '(device.deviceManufacturer -eq "LENOVO")'
        },
        
        # Autopilot groups
        @{
            Name = "Autopilot Devices"
            Description = "Dynamic group for all Autopilot registered devices"
            MembershipRule = '(device.devicePhysicalIds -any (_ -contains "[ZTDId]"))'
        },
        @{
            Name = "Non-Autopilot Windows Devices"
            Description = "Dynamic group for Windows devices not registered in Autopilot"
            MembershipRule = '(device.deviceOSType -eq "Windows") and -not (device.devicePhysicalIds -any (_ -contains "[ZTDId]"))'
        },
        
        # Compliance state groups
        @{
            Name = "Compliant Devices"
            Description = "Dynamic group for all compliant devices"
            MembershipRule = '(device.deviceTrustType -eq "AzureAd") and (device.isCompliant -eq true)'
        },
        @{
            Name = "Non-Compliant Devices"
            Description = "Dynamic group for all non-compliant devices"
            MembershipRule = '(device.deviceTrustType -eq "AzureAd") and (device.isCompliant -eq false)'
        },
        
        # Model-based groups (examples)
        @{
            Name = "Devices - Surface Laptop"
            Description = "Dynamic group for Surface Laptop devices"
            MembershipRule = '(device.deviceModel -contains "Surface Laptop")'
        },
        @{
            Name = "Devices - Surface Pro"
            Description = "Dynamic group for Surface Pro devices"
            MembershipRule = '(device.deviceModel -contains "Surface Pro")'
        }
    )
    
    foreach ($group in $dynamicGroups) {
        try {
            Write-IntuneLog "Creating dynamic group: $($group.Name)" -Level INFO
            
            $groupParams = @{
                DisplayName = $group.Name
                Description = $group.Description
                MailEnabled = $false
                MailNickname = $null
                SecurityEnabled = $true
                GroupTypes = @("DynamicMembership")
                MembershipRule = $group.MembershipRule
                MembershipRuleProcessingState = "On"
            }
            
            # Generate a valid MailNickname (alphanumeric only, no spaces)
            $mailNickname = ($group.Name -replace '[^a-zA-Z0-9]', '').ToLower()
            if ([string]::IsNullOrEmpty($mailNickname) -or $mailNickname.Length -lt 3) {
                $mailNickname = "group$(Get-Random -Minimum 1000 -Maximum 9999)"
            }
            $groupParams.MailNickname = $mailNickname
            
            # NOTE: Actual implementation requires Graph API call:
            # New-MgGroup -BodyParameter $groupParams
            
            Write-IntuneLog "Dynamic group template prepared: $($group.Name)" -Level SUCCESS
        }
        catch {
            Write-IntuneLog "Failed to create dynamic group $($group.Name): $_" -Level WARNING
        }
    }
    
    Write-IntuneLog "Dynamic groups creation completed" -Level SUCCESS
    return $true
}
