function Invoke-IntuneHydration {
    <#
    .SYNOPSIS
        Hydrates Microsoft Intune with policies, baselines, profiles, groups, and Conditional Access policies
    
    .DESCRIPTION
        This function orchestrates the complete Intune hydration process, importing:
        - OpenIntuneBaseline policies
        - Compliance baseline pack
        - Microsoft Security Baselines
        - Autopilot and ESP enrollment profiles
        - Dynamic groups for device categorization
        - Conditional Access policies (disabled by default)
    
    .PARAMETER SkipPolicies
        Skip importing OpenIntuneBaseline policies
    
    .PARAMETER SkipCompliance
        Skip importing compliance baselines
    
    .PARAMETER SkipSecurityBaselines
        Skip importing Microsoft Security Baselines
    
    .PARAMETER SkipEnrollment
        Skip creating Autopilot and ESP profiles
    
    .PARAMETER SkipGroups
        Skip creating dynamic groups
    
    .PARAMETER SkipConditionalAccess
        Skip importing Conditional Access policies
    
    .PARAMETER TenantId
        Azure AD Tenant ID (optional, will prompt if not provided)
    
    .PARAMETER LogPath
        Custom path for log files (optional, defaults to module directory/Logs)
    
    .PARAMETER KeepTempFiles
        Do not clean up temporary repository files after completion
    
    .EXAMPLE
        Invoke-IntuneHydration
        Run the full hydration process with interactive authentication
    
    .EXAMPLE
        Invoke-IntuneHydration -SkipEnrollment -SkipGroups
        Run hydration but skip enrollment profiles and dynamic groups
    
    .EXAMPLE
        Invoke-IntuneHydration -TenantId "your-tenant-id" -LogPath "C:\Logs"
        Run with specific tenant and custom log path
    
    .OUTPUTS
        Boolean indicating success or failure of the hydration process
    
    .NOTES
        Requires: Microsoft.Graph.* modules (will attempt to install if missing)
        Requires: Git installed and in PATH
        Requires: Internet connectivity
        Requires: Intune Administrator or Global Administrator role
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$SkipPolicies,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipCompliance,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipSecurityBaselines,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipEnrollment,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipGroups,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipConditionalAccess,
        
        [Parameter(Mandatory=$false)]
        [string]$TenantId,
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$KeepTempFiles
    )
    
    begin {
        # Initialize module variables
        if ($LogPath) {
            $Script:LogPath = $LogPath
        }
        else {
            $Script:LogPath = Join-Path $PSScriptRoot "Logs"
        }
        
        $Script:LogFile = Join-Path $Script:LogPath "IntuneHydration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $Script:TempPath = Join-Path $PSScriptRoot "Temp"
        
        Write-IntuneLog "========== Starting Intune Hydration Process ==========" -Level INFO
        Write-IntuneLog "Module Version: 1.0.0" -Level INFO
        Write-IntuneLog "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
    }
    
    process {
        try {
            # Check prerequisites
            if (-not (Test-IntunePrerequisites)) {
                Write-IntuneLog "Prerequisites check failed. Exiting." -Level ERROR
                return $false
            }
            
            # Connect to Microsoft Graph
            if (-not (Connect-IntuneGraph -TenantId $TenantId)) {
                Write-IntuneLog "Failed to connect to Microsoft Graph. Exiting." -Level ERROR
                return $false
            }
            
            # Import OpenIntuneBaseline policies
            if (-not $SkipPolicies) {
                Import-IntuneOpenBaseline
            }
            else {
                Write-IntuneLog "Skipping OpenIntuneBaseline policies import" -Level WARNING
            }
            
            # Import compliance baselines
            if (-not $SkipCompliance) {
                Import-IntuneComplianceBaselines
            }
            else {
                Write-IntuneLog "Skipping compliance baselines import" -Level WARNING
            }
            
            # Import security baselines
            if (-not $SkipSecurityBaselines) {
                Import-IntuneSecurityBaselines
            }
            else {
                Write-IntuneLog "Skipping security baselines import" -Level WARNING
            }
            
            # Create enrollment profiles
            if (-not $SkipEnrollment) {
                New-IntuneEnrollmentProfiles
            }
            else {
                Write-IntuneLog "Skipping enrollment profiles creation" -Level WARNING
            }
            
            # Create dynamic groups
            if (-not $SkipGroups) {
                New-IntuneDynamicGroups
            }
            else {
                Write-IntuneLog "Skipping dynamic groups creation" -Level WARNING
            }
            
            # Import Conditional Access policies
            if (-not $SkipConditionalAccess) {
                Import-IntuneConditionalAccessPolicies
            }
            else {
                Write-IntuneLog "Skipping Conditional Access policies import" -Level WARNING
            }
            
            Write-IntuneLog "========== Intune Hydration Process Completed ==========" -Level SUCCESS
            Write-IntuneLog "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
            Write-IntuneLog "Log file saved to: $Script:LogFile" -Level INFO
            
            return $true
        }
        catch {
            Write-IntuneLog "Critical error in hydration process: $_" -Level ERROR
            return $false
        }
    }
    
    end {
        # Cleanup
        if (-not $KeepTempFiles) {
            Write-IntuneLog "Cleaning up temporary files..." -Level INFO
            if (Test-Path $Script:TempPath) {
                Remove-Item -Path $Script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-IntuneLog "Keeping temporary files at: $Script:TempPath" -Level INFO
        }
        
        # Disconnect from Microsoft Graph
        try {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            Write-IntuneLog "Disconnected from Microsoft Graph" -Level INFO
        }
        catch {
            # Silently continue
        }
        
        Write-IntuneLog "Please review the log file for any warnings or errors." -Level INFO
        Write-IntuneLog "Remember to review and enable Conditional Access policies as needed." -Level WARNING
    }
}
