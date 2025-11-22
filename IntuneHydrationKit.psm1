#Requires -Version 7.0

<#
.SYNOPSIS
    Root module for IntuneHydrationKit
.DESCRIPTION
    Hydrates Microsoft Intune tenants with best-practice baseline configurations.
#>

# Module-level variables
$script:ModuleRoot = $PSScriptRoot
$script:TemplatesPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Templates'
$script:HydrationState = @{
    Connected = $false
    TenantId = $null
    Results = @{
        Groups = @()
        Policies = @()
        Baselines = @()
        Profiles = @()
        ConditionalAccess = @()
        Errors = @()
        Warnings = @()
    }
}

# Import helper modules
$helpersPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Scripts/Modules/Helpers.psm1'
if (Test-Path -Path $helpersPath) {
    Import-Module -Name $helpersPath -Force
}

# Helper function for creating standardized result objects
function New-HydrationResult {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Type,
        [string]$Action,
        [string]$Status,
        [string]$Id,
        [string]$Platform,
        [string]$State
    )
    $result = [PSCustomObject]@{
        Name = $Name
        Action = $Action
        Status = $Status
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    if ($Path) { $result | Add-Member -NotePropertyName 'Path' -NotePropertyValue $Path }
    if ($Type) { $result | Add-Member -NotePropertyName 'Type' -NotePropertyValue $Type }
    if ($Id) { $result | Add-Member -NotePropertyName 'Id' -NotePropertyValue $Id }
    if ($Platform) { $result | Add-Member -NotePropertyName 'Platform' -NotePropertyValue $Platform }
    if ($State) { $result | Add-Member -NotePropertyName 'State' -NotePropertyValue $State }
    return $result
}

# Helper function for calculating result summaries
function Get-ResultSummary {
    param([array]$Results)
    @{
        Created = ($Results | Where-Object { $_.Action -eq 'Created' }).Count
        Updated = ($Results | Where-Object { $_.Action -eq 'Updated' }).Count
        Skipped = ($Results | Where-Object { $_.Action -eq 'Skipped' }).Count
        Failed = ($Results | Where-Object { $_.Action -eq 'Failed' }).Count
    }
}

# Import all public functions
$publicFunctions = @(
    'Invoke-IntuneHydration',
    'Connect-IntuneHydration',
    'Test-IntunePrerequisites',
    'New-IntuneDynamicGroup',
    'Get-OpenIntuneBaseline',
    'Import-IntuneBaseline',
    'Import-IntuneCompliancePolicy',
    'Import-IntuneAppProtectionPolicy',
    'Import-IntuneNotificationTemplate',
    'Import-IntuneEnrollmentProfile',
    'Import-IntuneDeviceFilter',
    'Import-IntuneConditionalAccessPolicy',
    'Get-HydrationSummary'
)

# Placeholder functions - to be implemented
function Invoke-IntuneHydration {
    <#
    .SYNOPSIS
        Main orchestrator for Intune tenant hydration
    .DESCRIPTION
        Executes the complete hydration workflow including authentication,
        pre-flight checks, and import of all baseline configurations.
    .PARAMETER SettingsPath
        Path to the settings JSON file
    .PARAMETER WhatIf
        Run in dry-run mode without making changes
    .PARAMETER Force
        Force update of existing configurations
    .EXAMPLE
        Invoke-IntuneHydration -SettingsPath ./settings.json
    .EXAMPLE
        Invoke-IntuneHydration -SettingsPath ./settings.json -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$SettingsPath,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Write-Information "Starting Intune Hydration Kit" -InformationAction Continue
    }

    process {
        # TODO: Implement orchestration logic
        throw [System.NotImplementedException]::new("Invoke-IntuneHydration not yet implemented")
    }

    end {
        Write-Information "Hydration complete" -InformationAction Continue
    }
}

function Connect-IntuneHydration {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune hydration
    .DESCRIPTION
        Establishes authentication to Microsoft Graph using interactive or certificate-based auth.
        Supports multiple cloud environments: Global (Commercial), USGov, USGovDoD, Germany, China.
    .PARAMETER TenantId
        The Azure AD tenant ID
    .PARAMETER ClientId
        Application (client) ID for certificate-based auth
    .PARAMETER CertificateThumbprint
        Certificate thumbprint for authentication
    .PARAMETER Interactive
        Use interactive authentication
    .PARAMETER Environment
        Graph environment: Global, USGov, USGovDoD, Germany, China
    .EXAMPLE
        Connect-IntuneHydration -TenantId "contoso.onmicrosoft.com" -Interactive
    .EXAMPLE
        Connect-IntuneHydration -TenantId "contoso.onmicrosoft.us" -Interactive -Environment USGov
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Certificate')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Certificate')]
        [ValidatePattern('^[A-Fa-f0-9]{40}$')]
        [string]$CertificateThumbprint,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'Germany', 'China')]
        [string]$Environment = 'Global'
    )

    $scopes = @(
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "Group.ReadWrite.All",
        "Policy.ReadWrite.ConditionalAccess",
        "Directory.ReadWrite.All"
    )

    # Store environment for use by other functions
    $script:GraphEnvironment = $Environment
    $script:GraphEndpoint = switch ($Environment) {
        'Global'    { 'https://graph.microsoft.com' }
        'USGov'     { 'https://graph.microsoft.us' }
        'USGovDoD'  { 'https://dod-graph.microsoft.us' }
        'Germany'   { 'https://graph.microsoft.de' }
        'China'     { 'https://microsoftgraph.chinacloudapi.cn' }
    }

    Write-Information "Connecting to $Environment environment ($script:GraphEndpoint)" -InformationAction Continue

    try {
        $connectParams = @{
            TenantId = $TenantId
            Environment = $Environment
            ErrorAction = 'Stop'
        }

        if ($Interactive) {
            $connectParams['Scopes'] = $scopes
        }
        else {
            $connectParams['ClientId'] = $ClientId
            $connectParams['CertificateThumbprint'] = $CertificateThumbprint
        }

        Connect-MgGraph @connectParams

        $script:HydrationState.Connected = $true
        $script:HydrationState.TenantId = $TenantId
        $script:HydrationState.Environment = $Environment

        Write-Information "Successfully connected to tenant: $TenantId ($Environment)" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        throw
    }
}

function Test-IntunePrerequisites {
    <#
    .SYNOPSIS
        Validates Intune tenant prerequisites
    .DESCRIPTION
        Checks for Intune license availability and MDM authority configuration
    .EXAMPLE
        Test-IntunePrerequisites
    #>
    [CmdletBinding()]
    param()

    Write-Information "Validating Intune prerequisites..." -InformationAction Continue

    $issues = @()

    try {
        # Check organization info and licenses
        $org = Invoke-MgGraphRequest -Method GET -Uri "v1.0/organization" -ErrorAction Stop
        $orgDetails = $org.value[0]

        Write-Information "Connected to: $($orgDetails.displayName)" -InformationAction Continue

        # Check for Intune service plan
        $subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "v1.0/subscribedSkus" -ErrorAction Stop

        $intuneServicePlans = @(
            'INTUNE_A',           # Intune Plan 1
            'INTUNE_EDU',         # Intune for Education
            'INTUNE_SMBIZ',       # Intune Small Business
            'AAD_PREMIUM',        # Azure AD Premium (includes some Intune features)
            'EMSPREMIUM'          # Enterprise Mobility + Security
        )

        $hasIntune = $false
        foreach ($sku in $subscribedSkus.value) {
            foreach ($plan in $sku.servicePlans) {
                if ($plan.servicePlanName -in $intuneServicePlans -and $plan.provisioningStatus -eq 'Success') {
                    $hasIntune = $true
                    Write-Information "Found Intune license: $($plan.servicePlanName)" -InformationAction Continue
                    break
                }
            }
            if ($hasIntune) { break }
        }

        if (-not $hasIntune) {
            $issues += "No active Intune license found. Please ensure Intune is licensed for this tenant."
        }

        # Check MDM Authority
        $mdmPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/policies/mobileDeviceManagementPolicies?`$select=displayName,id,isValid" -ErrorAction Stop

        $intuneMdm = $mdmPolicies.value | Where-Object { $_.displayName -eq 'Microsoft Intune' -or $_.displayName -eq 'Microsoft Intune Enrollment' }

        if (-not $intuneMdm) {
            $issues += "MDM Authority is not configured. Please set up Microsoft Intune as the MDM authority."
        }
        elseif ($intuneMdm | Where-Object { $_.isValid -eq $false }) {
            $issues += "Microsoft Intune MDM policy exists but is not valid. Please verify MDM authority configuration."
        }
        else {
            Write-Information "MDM Authority: Microsoft Intune (OK)" -InformationAction Continue
        }

        # Report results
        if ($issues.Count -gt 0) {
            foreach ($issue in $issues) {
                Write-Warning $issue
            }
            throw "Prerequisite checks failed. Please resolve the issues above before continuing."
        }

        Write-Information "All prerequisite checks passed" -InformationAction Continue
        return $true
    }
    catch {
        if ($_.Exception.Message -match "Prerequisite checks failed") {
            throw
        }
        Write-Error "Failed to validate prerequisites: $_"
        throw
    }
}

function New-IntuneDynamicGroup {
    <#
    .SYNOPSIS
        Creates a dynamic Azure AD group for Intune
    .DESCRIPTION
        Creates a dynamic group with the specified membership rule. If a group with the same name exists, returns the existing group.
    .PARAMETER DisplayName
        The display name for the group
    .PARAMETER Description
        Description of the group
    .PARAMETER MembershipRule
        OData membership rule for dynamic membership
    .PARAMETER MembershipRuleProcessingState
        Processing state for the rule (On or Paused)
    .EXAMPLE
        New-IntuneDynamicGroup -DisplayName "Windows 11 Devices" -MembershipRule "(device.operatingSystem -eq 'Windows') and (device.operatingSystemVersion -startsWith '10.0.22')"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter()]
        [string]$Description = "",

        [Parameter(Mandatory = $true)]
        [string]$MembershipRule,

        [Parameter()]
        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState = 'On'
    )

    try {
        # Check if group already exists
        $existingGroups = Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$DisplayName'" -ErrorAction Stop

        if ($existingGroups.value.Count -gt 0) {
            $existingGroup = $existingGroups.value[0]
            Write-Information "Group already exists: $DisplayName (ID: $($existingGroup.id))" -InformationAction Continue
            return New-HydrationResult -Name $existingGroup.displayName -Id $existingGroup.id -Action 'Skipped' -Status 'Group already exists'
        }

        # Create new dynamic group
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create dynamic group")) {
            $groupBody = @{
                displayName = $DisplayName
                description = $Description
                mailEnabled = $false
                mailNickname = ($DisplayName -replace '[^a-zA-Z0-9]', '')
                securityEnabled = $true
                groupTypes = @('DynamicMembership')
                membershipRule = $MembershipRule
                membershipRuleProcessingState = $MembershipRuleProcessingState
            }

            $newGroup = Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups" -Body $groupBody -ErrorAction Stop

            Write-Information "Created group: $DisplayName (ID: $($newGroup.id))" -InformationAction Continue

            return New-HydrationResult -Name $newGroup.displayName -Id $newGroup.id -Action 'Created' -Status 'New group created'
        }
        else {
            return New-HydrationResult -Name $DisplayName -Action 'Skipped' -Status 'WhatIf mode'
        }
    }
    catch {
        Write-Error "Failed to create group '$DisplayName': $_"
        return New-HydrationResult -Name $DisplayName -Action 'Failed' -Status $_.Exception.Message
    }
}

function Get-OpenIntuneBaseline {
    <#
    .SYNOPSIS
        Downloads OpenIntuneBaseline repository from GitHub
    .DESCRIPTION
        Downloads and extracts the OpenIntuneBaseline repository containing all baseline policies
    .PARAMETER RepoUrl
        GitHub repository URL (default: https://github.com/SkipToTheEndpoint/OpenIntuneBaseline)
    .PARAMETER Branch
        Branch to download (default: main)
    .PARAMETER DestinationPath
        Path to extract the repository (default: temp directory)
    .EXAMPLE
        Get-OpenIntuneBaseline -DestinationPath ./Baselines
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RepoUrl = "https://github.com/SkipToTheEndpoint/OpenIntuneBaseline",

        [Parameter()]
        [string]$Branch = "main",

        [Parameter()]
        [string]$DestinationPath
    )

    if (-not $DestinationPath) {
        $DestinationPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OpenIntuneBaseline"
    }

    $zipUrl = "$RepoUrl/archive/refs/heads/$Branch.zip"
    $zipPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OpenIntuneBaseline-$Branch.zip"

    try {
        Write-Information "Downloading OpenIntuneBaseline from $zipUrl" -InformationAction Continue

        # Download the repository
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop

        # Clean existing directory if present
        if (Test-Path -Path $DestinationPath) {
            Remove-Item -Path $DestinationPath -Recurse -Force
        }

        # Extract
        Expand-Archive -Path $zipPath -DestinationPath $DestinationPath -Force

        # The archive extracts to a subfolder, move contents up
        $extractedFolder = Get-ChildItem -Path $DestinationPath -Directory | Select-Object -First 1
        if ($extractedFolder) {
            $tempMove = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OIB-temp-$(Get-Random)"
            Move-Item -Path $extractedFolder.FullName -Destination $tempMove
            Remove-Item -Path $DestinationPath -Force
            Move-Item -Path $tempMove -Destination $DestinationPath
        }

        # Clean up zip
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

        Write-Information "OpenIntuneBaseline downloaded to: $DestinationPath" -InformationAction Continue

        return $DestinationPath
    }
    catch {
        Write-Error "Failed to download OpenIntuneBaseline: $_"
        throw
    }
}

function Import-IntuneBaseline {
    <#
    .SYNOPSIS
        Imports OpenIntuneBaseline policies using IntuneManagement module
    .DESCRIPTION
        Downloads OpenIntuneBaseline from GitHub and imports all policies using the IntuneManagement module.
        Uses IntuneManagement's silent batch mode for automated imports.
    .PARAMETER BaselinePath
        Path to the OpenIntuneBaseline directory (will download if not specified)
    .PARAMETER IntuneManagementPath
        Path to IntuneManagement module (will download if not specified)
    .PARAMETER TenantId
        Target tenant ID (uses connected tenant if not specified)
    .PARAMETER ImportMode
        Import mode: AlwaysImport, SkipIfExists, Replace, Update
    .PARAMETER IncludeAssignments
        Include policy assignments during import
    .EXAMPLE
        Import-IntuneBaseline
    .EXAMPLE
        Import-IntuneBaseline -BaselinePath ./OpenIntuneBaseline -ImportMode SkipIfExists
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$BaselinePath,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [ValidateSet('SkipIfExists', 'Replace')]
        [string]$ImportMode = 'SkipIfExists'
    )

    # Use connected tenant if not specified
    if (-not $TenantId -and $script:HydrationState.TenantId) {
        $TenantId = $script:HydrationState.TenantId
    }

    if (-not $TenantId) {
        throw "TenantId is required. Either connect using Connect-IntuneHydration or specify -TenantId parameter."
    }

    # Download OpenIntuneBaseline if not provided
    if (-not $BaselinePath -or -not (Test-Path -Path $BaselinePath)) {
        $BaselinePath = Get-OpenIntuneBaseline
    }

    # OpenIntuneBaseline uses OS-based folder structure:
    # - OS/IntuneManagement/ - Exported by IntuneManagement tool (requires Windows GUI to import)
    # - OS/NativeImport/ - Settings Catalog policies that can be imported via Graph API
    # - BYOD/AppProtection/ - App protection policies

    # Map folder names to Graph API endpoints
    $endpointMap = @{
        'NativeImport'                      = 'deviceManagement/configurationPolicies'
        'AppProtection'                     = 'deviceAppManagement/managedAppPolicies'
        'Administrative Templates'           = 'deviceManagement/groupPolicyConfigurations'
        'Compliance'                        = 'deviceManagement/deviceCompliancePolicies'
        'Compliance Policies'               = 'deviceManagement/deviceCompliancePolicies'
        'Configuration Profiles'            = 'deviceManagement/deviceConfigurations'
        'Device Configuration'              = 'deviceManagement/deviceConfigurations'
        'Device Enrollment Configurations'  = 'deviceManagement/deviceEnrollmentConfigurations'
        'Endpoint Security'                 = 'deviceManagement/intents'
        'Settings Catalog'                  = 'deviceManagement/configurationPolicies'
        'Scripts'                           = 'deviceManagement/deviceManagementScripts'
        'Proactive Remediations'            = 'deviceManagement/deviceHealthScripts'
        'Windows Autopilot'                 = 'deviceManagement/windowsAutopilotDeploymentProfiles'
        'App Configuration'                 = 'deviceAppManagement/mobileAppConfigurations'
        'App Protection'                    = 'deviceAppManagement/managedAppPolicies'
        'App Protection Policies'           = 'deviceAppManagement/managedAppPolicies'
    }

    # Map @odata.type to Graph API endpoints for IntuneManagement exports
    $odataTypeToEndpoint = @{
        # Device Configurations
        '#microsoft.graph.windowsHealthMonitoringConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10GeneralConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10EndpointProtectionConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10CustomConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsDeliveryOptimizationConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsUpdateForBusinessConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsIdentityProtectionConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsKioskConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.editionUpgradeConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.sharedPCConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsWifiConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsWiredNetworkConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSCustomConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSEndpointProtectionConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.iosGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.iosCustomConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.androidGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.androidWorkProfileGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        # Compliance Policies
        '#microsoft.graph.windows10CompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.windows81CompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.macOSCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.iosCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidWorkProfileCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidDeviceOwnerCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
    }

    # Folders that previously required IntuneManagement tool - now we try to import via Graph API
    $intuneManagementFolders = @('IntuneManagement')

    # Find all policy type subfolders within OS folders (WINDOWS, MACOS, BYOD, WINDOWS365)
    # OpenIntuneBaseline structure: OS/PolicyType/policy.json
    $osFolders = Get-ChildItem -Path $BaselinePath -Directory | Where-Object {
        $_.Name -notmatch '^\.'
    }

    $results = @()
    $totalPolicies = 0
    $policyTypefolders = @()

    foreach ($osFolder in $osFolders) {
        # Get policy type subfolders within each OS folder
        $subFolders = Get-ChildItem -Path $osFolder.FullName -Directory | Where-Object {
            $_.Name -notmatch '^\.' -and (Get-ChildItem -Path $_.FullName -Filter "*.json" -File -Recurse).Count -gt 0
        }

        foreach ($subFolder in $subFolders) {
            $jsonFiles = Get-ChildItem -Path $subFolder.FullName -Filter "*.json" -File -Recurse
            $totalPolicies += $jsonFiles.Count
            $policyTypefolders += @{
                Folder = $subFolder
                OsFolder = $osFolder.Name
                PolicyType = $subFolder.Name
            }
            Write-Information "Found $($jsonFiles.Count) policies in $($osFolder.Name)/$($subFolder.Name)" -InformationAction Continue
        }
    }

    Write-Information "Total policies to import: $totalPolicies" -InformationAction Continue

    if ($PSCmdlet.ShouldProcess("$totalPolicies policies from OpenIntuneBaseline", "Import to Intune")) {
        Write-Information "Starting direct Graph API import..." -InformationAction Continue

        foreach ($policyFolder in $policyTypefolders) {
            $folder = $policyFolder.Folder
            $folderName = $policyFolder.PolicyType
            $osName = $policyFolder.OsFolder
            $jsonFiles = Get-ChildItem -Path $folder.FullName -Filter "*.json" -File -Recurse

            # For IntuneManagement folders, try to import using @odata.type routing
            if ($folderName -in $intuneManagementFolders) {
                Write-Information "Processing $osName/$folderName - attempting Graph API import..." -InformationAction Continue

                foreach ($jsonFile in $jsonFiles) {
                    $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                    try {
                        $policyContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json
                        $odataType = $policyContent.'@odata.type'

                        # Determine endpoint from @odata.type
                        $typeEndpoint = $odataTypeToEndpoint[$odataType]
                        if (-not $typeEndpoint) {
                            Write-Warning "  Skipping $policyName - unsupported @odata.type: $odataType"
                            $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status "Unsupported @odata.type: $odataType"
                            continue
                        }

                        # Get display name
                        $displayName = $policyContent.displayName
                        if (-not $displayName) {
                            $displayName = $policyName
                        }

                        # Check if policy exists
                        $existingPolicy = $existingPolicies.ContainsKey($displayName)
                        if (-not $existingPolicy) {
                            # Fetch from this specific endpoint
                            try {
                                $checkUri = "beta/$typeEndpoint"
                                $checkResponse = Invoke-MgGraphRequest -Method GET -Uri $checkUri -ErrorAction Stop
                                $existingPolicy = $checkResponse.value | Where-Object { $_.displayName -eq $displayName }
                            }
                            catch {
                                $existingPolicy = $null
                            }
                        }

                        if ($existingPolicy -and $ImportMode -eq 'SkipIfExists') {
                            Write-Information "  Skipping existing: $displayName" -InformationAction Continue
                            $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'Already exists'
                            continue
                        }

                        # Prepare import body - remove read-only and assignment properties
                        $importBody = $policyContent | ConvertTo-Json -Depth 100 | ConvertFrom-Json

                        $propsToRemove = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version',
                                           'supportsScopeTags', 'deviceManagementApplicabilityRuleOsEdition',
                                           'deviceManagementApplicabilityRuleOsVersion',
                                           'deviceManagementApplicabilityRuleDeviceMode',
                                           '@odata.context', '@odata.id', '@odata.editLink',
                                           'creationSource', 'settingCount', 'priorityMetaData',
                                           'assignments')

                        foreach ($prop in $propsToRemove) {
                            if ($importBody.PSObject.Properties[$prop]) {
                                $importBody.PSObject.Properties.Remove($prop)
                            }
                        }

                        # Remove properties with @odata.type annotations (metadata)
                        $metadataProps = $importBody.PSObject.Properties | Where-Object { $_.Name -match '@odata\.' -and $_.Name -ne '@odata.type' }
                        foreach ($prop in $metadataProps) {
                            $importBody.PSObject.Properties.Remove($prop.Name)
                        }

                        # Clean up scheduledActionsForRule - remove nested @odata.context and IDs
                        if ($importBody.scheduledActionsForRule) {
                            $cleanedActions = @()
                            foreach ($action in $importBody.scheduledActionsForRule) {
                                $cleanAction = @{
                                    ruleName = $action.ruleName
                                }
                                if ($action.scheduledActionConfigurations) {
                                    $cleanConfigs = @()
                                    foreach ($config in $action.scheduledActionConfigurations) {
                                        # Ensure notificationMessageCCList is always an array, never null
                                        $ccList = @()
                                        if ($null -ne $config.notificationMessageCCList -and $config.notificationMessageCCList.Count -gt 0) {
                                            $ccList = @($config.notificationMessageCCList)
                                        }
                                        $cleanConfig = @{
                                            actionType = $config.actionType
                                            gracePeriodHours = [int]$config.gracePeriodHours
                                            notificationTemplateId = if ($config.notificationTemplateId) { $config.notificationTemplateId } else { "" }
                                            notificationMessageCCList = $ccList
                                        }
                                        $cleanConfigs += $cleanConfig
                                    }
                                    $cleanAction.scheduledActionConfigurations = $cleanConfigs
                                }
                                $cleanedActions += $cleanAction
                            }
                            $importBody.scheduledActionsForRule = $cleanedActions
                        }

                        # Create the policy
                        $response = Invoke-MgGraphRequest -Method POST -Uri "beta/$typeEndpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop

                        Write-Information "  Created: $displayName" -InformationAction Continue
                        $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Created' -Status 'Success'
                    }
                    catch {
                        $errorMsg = $_.Exception.Message
                        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                            $errorMsg = $_.ErrorDetails.Message
                        }
                        Write-Warning "  Failed: $policyName - $errorMsg"
                        $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status $errorMsg
                    }

                    Start-Sleep -Milliseconds 100
                }
                continue
            }

            # Determine API endpoint based on policy type folder name
            $endpoint = $endpointMap[$folderName]
            if (-not $endpoint) {
                Write-Warning "No endpoint mapping for folder: $osName/$folderName - skipping"
                foreach ($jsonFile in $jsonFiles) {
                    $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)
                    $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status "No endpoint mapping for $folderName"
                }
                continue
            }

            Write-Information "Importing $($jsonFiles.Count) items from $osName/$folderName..." -InformationAction Continue

            # Pre-fetch existing policies for this endpoint to avoid repeated API calls (page through all results)
            $existingPolicies = @{}
            try {
                $listUri = "beta/$endpoint"
                do {
                    $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                    foreach ($policy in $existingResponse.value) {
                        $policyDisplayName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                        if ($policyDisplayName -and -not $existingPolicies.ContainsKey($policyDisplayName)) {
                            $existingPolicies[$policyDisplayName] = $policy.id
                        }
                    }
                    $listUri = $existingResponse.'@odata.nextLink'
                } while ($listUri)
            }
            catch {
                # Endpoint might not support listing, continue without cache
            }

            foreach ($jsonFile in $jsonFiles) {
                $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                try {
                    # Read and parse JSON
                    $policyContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json

                    # Get display name from policy
                    $displayName = $policyContent.displayName
                    if (-not $displayName) {
                        $displayName = $policyContent.name
                    }
                    if (-not $displayName) {
                        $displayName = $policyName
                    }

                    # Check if policy exists using cached list
                    $existingPolicy = $existingPolicies.ContainsKey($displayName)

                    if ($existingPolicy -and $ImportMode -eq 'SkipIfExists') {
                        Write-Information "  Skipping existing: $displayName" -InformationAction Continue
                        $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'Already exists'
                        continue
                    }

                    # Clean up import properties that shouldn't be sent
                    $importBody = $policyContent | ConvertTo-Json -Depth 100 | ConvertFrom-Json

                    # Remove read-only and system properties
                    $propsToRemove = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version',
                                       'supportsScopeTags', 'deviceManagementApplicabilityRuleOsEdition',
                                       'deviceManagementApplicabilityRuleOsVersion',
                                       'deviceManagementApplicabilityRuleDeviceMode',
                                       '@odata.context', 'creationSource', 'settingCount', 'priorityMetaData')

                    foreach ($prop in $propsToRemove) {
                        if ($importBody.PSObject.Properties[$prop]) {
                            $importBody.PSObject.Properties.Remove($prop)
                        }
                    }

                    # Create or update the policy
                    if ($existingPolicy -and $ImportMode -eq 'Replace') {
                        # Delete and recreate
                        $existingId = $existingPolicies[$displayName]
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/$endpoint/$existingId" -ErrorAction Stop
                        $response = Invoke-MgGraphRequest -Method POST -Uri "beta/$endpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                        $action = 'Updated'
                    }
                    else {
                        $response = Invoke-MgGraphRequest -Method POST -Uri "beta/$endpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                        $action = 'Created'
                    }

                    Write-Information "  $action : $displayName" -InformationAction Continue

                    $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action $action -Status 'Success'
                }
                catch {
                    $errorMsg = $_.Exception.Message
                    Write-Warning "  Failed: $policyName - $errorMsg"

                    $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status $errorMsg
                }

                # Small delay to avoid rate limiting
                Start-Sleep -Milliseconds 100
            }
        }

        $summary = Get-ResultSummary -Results $results

        Write-Information "Import completed. Created: $($summary.Created), Updated: $($summary.Updated), Skipped: $($summary.Skipped), Failed: $($summary.Failed)" -InformationAction Continue
    }
    else {
        # WhatIf mode - just report what would be imported
        foreach ($policyFolder in $policyTypefolders) {
            $folder = $policyFolder.Folder
            $osName = $policyFolder.OsFolder
            $folderName = $policyFolder.PolicyType
            $jsonFiles = Get-ChildItem -Path $folder.FullName -Filter "*.json" -File -Recurse

            foreach ($jsonFile in $jsonFiles) {
                $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'DryRun'
            }
        }
    }

    return $results
}

function Import-IntuneEnrollmentProfile {
    <#
    .SYNOPSIS
        Imports enrollment profiles
    .DESCRIPTION
        Creates Windows Autopilot deployment profiles and Enrollment Status Page configurations.
        Optionally creates Apple enrollment profiles if ABM is enabled.
    .PARAMETER TemplatePath
        Path to the enrollment template directory
    .PARAMETER DeviceNameTemplate
        Custom device naming template (default: %SERIAL%)
    .EXAMPLE
        Import-IntuneEnrollmentProfile
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [string]$DeviceNameTemplate
    )

    # Use default template path if not specified
    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Enrollment"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        throw "Enrollment template directory not found: $TemplatePath"
    }

    $results = @()

    #region Windows Autopilot Deployment Profile
    $autopilotTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-Autopilot-Profile.json"

    if (Test-Path -Path $autopilotTemplatePath) {
        $autopilotTemplate = Get-Content -Path $autopilotTemplatePath -Raw | ConvertFrom-Json
        $profileName = $autopilotTemplate.displayName

        try {
            # Check if profile exists
            $existingProfiles = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$profileName'" -ErrorAction Stop

            if ($existingProfiles.value.Count -gt 0) {
                Write-Information "Autopilot profile already exists: $profileName" -InformationAction Continue
                $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $existingProfiles.value[0].id -Action 'Skipped' -Status 'Already exists'
            }
            elseif ($PSCmdlet.ShouldProcess($profileName, "Create Autopilot deployment profile")) {
                # Build profile body with all required properties
                $language = if ([string]::IsNullOrWhiteSpace($autopilotTemplate.language)) { 'en-US' } else { $autopilotTemplate.language }
                $profileBody = @{
                    "@odata.type" = "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile"
                    displayName = $autopilotTemplate.displayName
                    description = $autopilotTemplate.description
                    deviceType = $autopilotTemplate.deviceType
                    deviceNameTemplate = if ($DeviceNameTemplate) { $DeviceNameTemplate } else { $autopilotTemplate.deviceNameTemplate }
                    language = $language
                    enableWhiteGlove = $autopilotTemplate.enableWhiteGlove
                    extractHardwareHash = $autopilotTemplate.extractHardwareHash
                    hybridAzureADJoinSkipConnectivityCheck = $autopilotTemplate.hybridAzureADJoinSkipConnectivityCheck
                    outOfBoxExperienceSettings = @{
                        hidePrivacySettings = $autopilotTemplate.outOfBoxExperienceSettings.hidePrivacySettings
                        hideEULA = $autopilotTemplate.outOfBoxExperienceSettings.hideEULA
                        userType = $autopilotTemplate.outOfBoxExperienceSettings.userType
                        deviceUsageType = $autopilotTemplate.outOfBoxExperienceSettings.deviceUsageType
                        skipKeyboardSelectionPage = $autopilotTemplate.outOfBoxExperienceSettings.skipKeyboardSelectionPage
                        hideEscapeLink = $autopilotTemplate.outOfBoxExperienceSettings.hideEscapeLink
                    }
                    roleScopeTagIds = @()
                }

                $jsonBody = $profileBody | ConvertTo-Json -Depth 10
                $newProfile = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/windowsAutopilotDeploymentProfiles" -Body $jsonBody -ContentType "application/json" -ErrorAction Stop

                Write-Information "Created Autopilot profile: $profileName (ID: $($newProfile.id))" -InformationAction Continue

                $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Id $newProfile.id -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            Write-Error "Failed to create Autopilot profile: $_"
            $results += New-HydrationResult -Name $profileName -Type 'AutopilotDeploymentProfile' -Action 'Failed' -Status $_.Exception.Message
        }
    }
    #endregion

    #region Enrollment Status Page
    $espTemplatePath = Join-Path -Path $TemplatePath -ChildPath "Windows-ESP-Profile.json"

    if (Test-Path -Path $espTemplatePath) {
        $espTemplate = Get-Content -Path $espTemplatePath -Raw | ConvertFrom-Json
        $espName = $espTemplate.displayName

        try {
            # Check if ESP exists
            $existingESP = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=displayName eq '$espName'" -ErrorAction Stop

            $customESP = $existingESP.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' -and $_.displayName -eq $espName }

            if ($customESP) {
                Write-Information "ESP profile already exists: $espName" -InformationAction Continue
                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Id $customESP.id -Action 'Skipped' -Status 'Already exists'
            }
            elseif ($PSCmdlet.ShouldProcess($espName, "Create Enrollment Status Page profile")) {
                # Build ESP body
                $espBody = @{
                    "@odata.type" = "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
                    displayName = $espTemplate.displayName
                    description = $espTemplate.description
                    showInstallationProgress = $espTemplate.showInstallationProgress
                    blockDeviceSetupRetryByUser = $espTemplate.blockDeviceSetupRetryByUser
                    allowDeviceResetOnInstallFailure = $espTemplate.allowDeviceResetOnInstallFailure
                    allowLogCollectionOnInstallFailure = $espTemplate.allowLogCollectionOnInstallFailure
                    customErrorMessage = $espTemplate.customErrorMessage
                    installProgressTimeoutInMinutes = $espTemplate.installProgressTimeoutInMinutes
                    allowDeviceUseOnInstallFailure = $espTemplate.allowDeviceUseOnInstallFailure
                    trackInstallProgressForAutopilotOnly = $espTemplate.trackInstallProgressForAutopilotOnly
                    disableUserStatusTrackingAfterFirstUser = $espTemplate.disableUserStatusTrackingAfterFirstUser
                }

                $newESP = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceEnrollmentConfigurations" -Body $espBody -ErrorAction Stop

                Write-Information "Created ESP profile: $espName (ID: $($newESP.id))" -InformationAction Continue

                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Id $newESP.id -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            Write-Error "Failed to create ESP profile: $_"
            $results += New-HydrationResult -Name $espName -Type 'EnrollmentStatusPage' -Action 'Failed' -Status $_.Exception.Message
        }
    }
    #endregion

    # Summary
    $summary = Get-ResultSummary -Results $results

    Write-Information "Enrollment profile import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}

function Import-IntuneDeviceFilter {
    <#
    .SYNOPSIS
        Creates device filters for Intune
    .DESCRIPTION
        Creates device filters by manufacturer for each device OS platform (Windows, macOS, iOS/iPadOS, Android).
        Creates 3 manufacturer filters per OS: Dell/HP/Lenovo for Windows, Apple for macOS/iOS.
    .EXAMPLE
        Import-IntuneDeviceFilter
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $results = @()

    # Get all existing filters first with pagination (OData filter on displayName not supported for this endpoint)
    $existingFilterNames = @{}
    try {
        $listUri = "beta/deviceManagement/assignmentFilters"
        do {
            $existingFiltersResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($existingFilter in $existingFiltersResponse.value) {
                if (-not $existingFilterNames.ContainsKey($existingFilter.displayName)) {
                    $existingFilterNames[$existingFilter.displayName] = $existingFilter.id
                }
            }
            $listUri = $existingFiltersResponse.'@odata.nextLink'
        } while ($listUri)
    }
    catch {
        Write-Warning "Could not retrieve existing filters: $_"
        $existingFilterNames = @{}
    }

    # Define filters: OS -> Manufacturer filters
    $filterDefinitions = @(
        # Windows filters by manufacturer
        @{
            DisplayName = "Windows - Dell Devices"
            Description = "Filter for Dell Windows devices"
            Platform = "windows10AndLater"
            Rule = '(device.manufacturer -eq "Dell Inc.")'
        },
        @{
            DisplayName = "Windows - HP Devices"
            Description = "Filter for HP Windows devices"
            Platform = "windows10AndLater"
            Rule = '(device.manufacturer -eq "HP") or (device.manufacturer -eq "Hewlett-Packard")'
        },
        @{
            DisplayName = "Windows - Lenovo Devices"
            Description = "Filter for Lenovo Windows devices"
            Platform = "windows10AndLater"
            Rule = '(device.manufacturer -eq "LENOVO")'
        },
        # macOS filters
        @{
            DisplayName = "macOS - Apple Devices"
            Description = "Filter for Apple macOS devices"
            Platform = "macOS"
            Rule = '(device.manufacturer -eq "Apple")'
        },
        @{
            DisplayName = "macOS - MacBook Devices"
            Description = "Filter for MacBook devices"
            Platform = "macOS"
            Rule = '(device.model -startsWith "MacBook")'
        },
        @{
            DisplayName = "macOS - iMac Devices"
            Description = "Filter for iMac devices"
            Platform = "macOS"
            Rule = '(device.model -startsWith "iMac")'
        },
        # iOS/iPadOS filters
        @{
            DisplayName = "iOS - iPhone Devices"
            Description = "Filter for iPhone devices"
            Platform = "iOS"
            Rule = '(device.model -startsWith "iPhone")'
        },
        @{
            DisplayName = "iOS - iPad Devices"
            Description = "Filter for iPad devices"
            Platform = "iOS"
            Rule = '(device.model -startsWith "iPad")'
        },
        @{
            DisplayName = "iOS - Corporate Owned"
            Description = "Filter for corporate-owned iOS/iPadOS devices"
            Platform = "iOS"
            Rule = '(device.deviceOwnership -eq "Corporate")'
        },
        # Android filters
        @{
            DisplayName = "Android - Samsung Devices"
            Description = "Filter for Samsung Android devices"
            Platform = "androidForWork"
            Rule = '(device.manufacturer -eq "samsung")'
        },
        @{
            DisplayName = "Android - Google Pixel Devices"
            Description = "Filter for Google Pixel devices"
            Platform = "androidForWork"
            Rule = '(device.manufacturer -eq "Google")'
        },
        @{
            DisplayName = "Android - Corporate Owned"
            Description = "Filter for corporate-owned Android devices"
            Platform = "androidForWork"
            Rule = '(device.deviceOwnership -eq "Corporate")'
        }
    )

    foreach ($filter in $filterDefinitions) {
        try {
            # Check if filter already exists using pre-fetched list
            if ($existingFilterNames.ContainsKey($filter.DisplayName)) {
                Write-Information "Filter already exists: $($filter.DisplayName)" -InformationAction Continue
                $results += New-HydrationResult -Name $filter.DisplayName -Id $existingFilterNames[$filter.DisplayName] -Platform $filter.Platform -Action 'Skipped' -Status 'Already exists'
                continue
            }

            if ($PSCmdlet.ShouldProcess($filter.DisplayName, "Create device filter")) {
                $filterBody = @{
                    displayName = $filter.DisplayName
                    description = $filter.Description
                    platform = $filter.Platform
                    rule = $filter.Rule
                    roleScopeTags = @("0")
                }

                $newFilter = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/assignmentFilters" -Body $filterBody -ErrorAction Stop

                Write-Information "Created filter: $($filter.DisplayName) (ID: $($newFilter.id))" -InformationAction Continue

                $results += New-HydrationResult -Name $filter.DisplayName -Id $newFilter.id -Platform $filter.Platform -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $filter.DisplayName -Platform $filter.Platform -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            Write-Error "Failed to create filter '$($filter.DisplayName)': $_"
            $results += New-HydrationResult -Name $filter.DisplayName -Platform $filter.Platform -Action 'Failed' -Status $_.Exception.Message
        }
    }

    # Summary
    $summary = Get-ResultSummary -Results $results

    Write-Information "Device filter import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}

function Import-IntuneAppProtectionPolicy {
    <#
    .SYNOPSIS
        Imports app protection (MAM) policies from templates
    .DESCRIPTION
        Reads app protection templates and upserts Android/iOS managed app protection policies via Graph.
    .PARAMETER TemplatePath
        Path to the app protection template directory (defaults to Templates/AppProtection)
    .EXAMPLE
        Import-IntuneAppProtectionPolicy
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "AppProtection"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "App protection template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File -Recurse
    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No app protection templates found in: $TemplatePath"
        return @()
    }

    $typeToEndpoint = @{
        '#microsoft.graph.androidManagedAppProtection' = 'beta/deviceAppManagement/androidManagedAppProtections'
        '#microsoft.graph.iosManagedAppProtection'     = 'beta/deviceAppManagement/iosManagedAppProtections'
    }

    $results = @()

    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $displayName = $template.displayName
            $odataType = $template.'@odata.type'

            if (-not $displayName -or -not $odataType) {
                Write-Warning "Template missing displayName or @odata.type: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'AppProtection' -Action 'Failed' -Status 'Missing displayName or @odata.type'
                continue
            }

            $endpoint = $typeToEndpoint[$odataType]
            if (-not $endpoint) {
                Write-Warning "Unsupported @odata.type '$odataType' in $($templateFile.FullName) - skipping"
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Skipped' -Status "Unsupported @odata.type: $odataType"
                continue
            }

            # Check for existing policy by display name with pagination
            $existingMatch = $null
            $listUri = $endpoint
            :paginationLoop do {
                $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                $existingMatch = $existing.value | Where-Object { $_.displayName -eq $displayName }
                if ($existingMatch) {
                    break paginationLoop
                }
                $listUri = $existing.'@odata.nextLink'
            } while ($listUri)

            if ($existingMatch) {
                Write-Information "App protection policy already exists: $displayName" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            # Prepare body (remove read-only properties)
            $importBody = $template | ConvertTo-Json -Depth 100 | ConvertFrom-Json
            $propsToRemove = @(
                'id',
                'createdDateTime',
                'lastModifiedDateTime',
                '@odata.context',
                'apps',
                'assignments',
                'targetedAppManagementLevels'
            )
            foreach ($prop in $propsToRemove) {
                if ($importBody.PSObject.Properties[$prop]) {
                    $importBody.PSObject.Properties.Remove($prop)
                }
            }

            # Remove empty manufacturer/model allowlists
            if ($importBody.allowedAndroidDeviceManufacturers -eq "") {
                $importBody.PSObject.Properties.Remove('allowedAndroidDeviceManufacturers') | Out-Null
            }
            if ($importBody.allowedIosDeviceModels -eq "") {
                $importBody.PSObject.Properties.Remove('allowedIosDeviceModels') | Out-Null
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create app protection policy")) {
                $response = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                Write-Information "Created app protection policy: $displayName (ID: $($response.id))" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Skipped' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $errMessage = $_.ErrorDetails.Message
            }
            elseif ($_.Exception.Response -and $_.Exception.Response.Content) {
                try {
                    $errBody = $_.Exception.Response.Content | ConvertFrom-Json -ErrorAction Stop
                    if ($errBody.error.message) {
                        $errMessage = $errBody.error.message
                    }
                }
                catch {
                    # ignore parse errors
                }
            }
            Write-Warning "Failed to import app protection policy from $($templateFile.FullName): $errMessage"
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'AppProtection' -Action 'Failed' -Status $errMessage
        }
    }

    $summary = Get-ResultSummary -Results $results

    Write-Information "App protection import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}

function Import-IntuneNotificationTemplate {
    <#
    .SYNOPSIS
        Imports notification message templates from JSON templates
    .DESCRIPTION
        Reads templates from Templates/Notifications and creates notificationMessageTemplates with localized messages.
    .PARAMETER TemplatePath
        Path to the notifications template directory (defaults to Templates/Notifications)
    .EXAMPLE
        Import-IntuneNotificationTemplate
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Notifications"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Notification template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File -Recurse
    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No notification templates found in: $TemplatePath"
        return @()
    }

    $results = @()

    # Prefetch existing templates
    $existingByName = @{}
    try {
        $listUri = "beta/deviceManagement/notificationMessageTemplates"
        do {
            $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($tmpl in $existingResponse.value) {
                if ($tmpl.displayName -and -not $existingByName.ContainsKey($tmpl.displayName)) {
                    $existingByName[$tmpl.displayName] = $tmpl.id
                }
            }
            $listUri = $existingResponse.'@odata.nextLink'
        } while ($listUri)
    }
    catch {
        $existingByName = @{}
    }

    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $displayName = $template.displayName

            if (-not $displayName) {
                Write-Warning "Template missing displayName: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Failed' -Status 'Missing displayName'
                continue
            }

            if ($existingByName.ContainsKey($displayName)) {
                Write-Information "Notification template already exists: $displayName" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            # Split template into main body and localized messages
            $localizedMessages = @()
            if ($template.localizedMessages) {
                $localizedMessages = $template.localizedMessages
                $template.PSObject.Properties.Remove('localizedMessages') | Out-Null
            }

            $importBody = $template | ConvertTo-Json -Depth 50 | ConvertFrom-Json

            if ($PSCmdlet.ShouldProcess($displayName, "Create notification template")) {
                $newTemplate = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/notificationMessageTemplates" -Body ($importBody | ConvertTo-Json -Depth 50) -ContentType "application/json" -ErrorAction Stop
                Write-Information "Created notification template: $displayName (ID: $($newTemplate.id))" -InformationAction Continue

                # Create localized messages if present
                foreach ($loc in $localizedMessages) {
                    try {
                        $locBody = $loc | ConvertTo-Json -Depth 20
                        Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/notificationMessageTemplates/$($newTemplate.id)/localizedNotificationMessages" -Body $locBody -ContentType "application/json" -ErrorAction Stop
                        Write-Information "  Added localized message ($($loc.locale))" -InformationAction Continue
                    }
                    catch {
                        Write-Warning "  Failed to add localized message ($($loc.locale)): $($_.Exception.Message)"
                    }
                }

                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Skipped' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $errMessage = $_.ErrorDetails.Message
            }
            Write-Warning "Failed to import notification template from $($templateFile.FullName): $errMessage"
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'NotificationTemplate' -Action 'Failed' -Status $errMessage
        }
    }

    $summary = Get-ResultSummary -Results $results

    Write-Information "Notification template import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}

function Import-IntuneCompliancePolicy {
    <#
    .SYNOPSIS
        Imports device compliance policies from templates
    .DESCRIPTION
        Reads JSON templates from Templates/Compliance and creates compliance policies via Graph.
    .PARAMETER TemplatePath
        Path to the compliance template directory (defaults to Templates/Compliance)
    .EXAMPLE
        Import-IntuneCompliancePolicy
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Compliance"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Compliance template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File -Recurse
    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No compliance templates found in: $TemplatePath"
        return @()
    }

    # Prefetch existing compliance policies (paged) from both classic and linux endpoints
    $existingByName = @{}
    $endpointsToList = @(
        "beta/deviceManagement/deviceCompliancePolicies",
        "beta/deviceManagement/compliancePolicies"
    )
    foreach ($listUriStart in $endpointsToList) {
        $listUri = $listUriStart
        try {
            do {
                $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                foreach ($policy in $existingResponse.value) {
                    $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                    if ($policyName -and -not $existingByName.ContainsKey($policyName)) {
                        $existingByName[$policyName] = $policy.id
                    }
                }
                $listUri = $existingResponse.'@odata.nextLink'
            } while ($listUri)
        }
        catch {
            continue
        }
    }

    $results = @()
    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $displayName = $template.displayName
            if (-not $displayName) {
                Write-Warning "Template missing displayName: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing displayName'
                continue
            }

            # Choose endpoint: Linux uses compliancePolicies, others use deviceCompliancePolicies
            $isLinuxCompliance = $template.platforms -eq 'linux' -and $template.technologies -eq 'linuxMdm'
            $endpoint = if ($isLinuxCompliance) {
                "beta/deviceManagement/compliancePolicies"
            } else {
                "beta/deviceManagement/deviceCompliancePolicies"
            }

            # For Linux, also consider 'name' when matching
            $lookupNames = @($displayName)
            if ($isLinuxCompliance -and $template.name) {
                $lookupNames += $template.name
            }

            $alreadyExists = $false
            foreach ($ln in $lookupNames) {
                if ($existingByName.ContainsKey($ln)) {
                    $alreadyExists = $true
                    break
                }
            }

            if ($alreadyExists) {
                Write-Information "Compliance policy already exists: $displayName" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            $importBody = $template | ConvertTo-Json -Depth 100 | ConvertFrom-Json
            $propsToRemove = @('id', 'createdDateTime', 'lastModifiedDateTime', '@odata.context', 'version')
            foreach ($prop in $propsToRemove) {
                if ($importBody.PSObject.Properties[$prop]) {
                    $importBody.PSObject.Properties.Remove($prop)
                }
            }

            # Linux endpoint expects 'name' instead of displayName; ensure it's present
            if ($isLinuxCompliance) {
                if (-not $importBody.name) {
                    $importBody | Add-Member -MemberType NoteProperty -Name name -Value $displayName -Force
                }
                # Some exports include displayName; keep it but ensure name is set
            }

            # Handle custom compliance policies with deviceCompliancePolicyScript
            # Uses the same approach as create-custom-compliance-policy.ps1
            if ($importBody.deviceCompliancePolicyScript) {
                $scriptDefinition = $template.deviceCompliancePolicyScriptDefinition
                $scriptDisplayName = if ($scriptDefinition.displayName) { $scriptDefinition.displayName } else { "$displayName Script" }

                # Step 1: Check if compliance script already exists or create it
                $scriptId = $null
                try {
                    $existingScripts = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceComplianceScripts" -ErrorAction Stop
                    $existingScript = $existingScripts.value | Where-Object { $_.displayName -eq $scriptDisplayName }

                    if ($existingScript) {
                        $scriptId = $existingScript.id
                        Write-Information "Using existing compliance script: $scriptDisplayName (ID: $scriptId)" -InformationAction Continue
                    }
                    elseif ($scriptDefinition -and $scriptDefinition.detectionScriptContentBase64) {
                        # Create the compliance script
                        $scriptBody = @{
                            description = if ($scriptDefinition.description) { $scriptDefinition.description } else { "" }
                            detectionScriptContent = $scriptDefinition.detectionScriptContentBase64
                            displayName = $scriptDisplayName
                            enforceSignatureCheck = [bool]$scriptDefinition.enforceSignatureCheck
                            publisher = if ($scriptDefinition.publisher) { $scriptDefinition.publisher } else { "Publisher" }
                            runAs32Bit = [bool]$scriptDefinition.runAs32Bit
                            runAsAccount = if ($scriptDefinition.runAsAccount) { $scriptDefinition.runAsAccount } else { "system" }
                        }

                        $newScript = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceComplianceScripts" -Body ($scriptBody | ConvertTo-Json -Depth 10) -ContentType "application/json" -ErrorAction Stop
                        $scriptId = $newScript.id
                        Write-Information "Created compliance script: $scriptDisplayName (ID: $scriptId)" -InformationAction Continue
                    }
                    else {
                        Write-Warning "Skipping compliance policy '$displayName' - no script definition found with detectionScriptContentBase64"
                        $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing detectionScriptContentBase64 in deviceCompliancePolicyScriptDefinition'
                        continue
                    }
                }
                catch {
                    Write-Warning "Failed to create/find compliance script for '$displayName': $($_.Exception.Message)"
                    $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status "Script error: $($_.Exception.Message)"
                    continue
                }

                # Step 2: Convert rules to base64
                $rulesSource = $scriptDefinition.rules
                if (-not $rulesSource) {
                    Write-Warning "Skipping compliance policy '$displayName' - no rules found in deviceCompliancePolicyScriptDefinition"
                    $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing rules in deviceCompliancePolicyScriptDefinition'
                    continue
                }

                $rulesJson = $rulesSource | ConvertTo-Json -Depth 100 -Compress
                $rulesBytes = [System.Text.Encoding]::UTF8.GetBytes($rulesJson)
                $rulesBase64 = [System.Convert]::ToBase64String($rulesBytes)

                # Step 3: Update the policy body with resolved values
                $importBody.deviceCompliancePolicyScript = @{
                    deviceComplianceScriptId = $scriptId
                    rulesContent = $rulesBase64
                }
            }

            # Remove internal helper definition before sending
            if ($importBody.PSObject.Properties['deviceCompliancePolicyScriptDefinition']) {
                $importBody.PSObject.Properties.Remove('deviceCompliancePolicyScriptDefinition') | Out-Null
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create compliance policy")) {
                $response = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                Write-Information "Created compliance policy: $displayName (ID: $($response.id))" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Skipped' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $errMessage = $_.ErrorDetails.Message
            }
            Write-Warning "Failed to import compliance policy from $($templateFile.FullName): $errMessage"
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status $errMessage
        }
    }

    $summary = Get-ResultSummary -Results $results

    Write-Information "Compliance import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}

function Import-IntuneConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Imports Conditional Access starter pack
    .DESCRIPTION
        Imports CA policies from templates with state forced to disabled.
        All policies are created in disabled state for safety.
    .PARAMETER TemplatePath
        Path to the CA template directory
    .PARAMETER Prefix
        Optional prefix to add to policy names
    .EXAMPLE
        Import-IntuneConditionalAccessPolicy -TemplatePath ./Templates/ConditionalAccess
    .EXAMPLE
        Import-IntuneConditionalAccessPolicy -TemplatePath ./Templates/ConditionalAccess -Prefix "Hydration - "
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [string]$Prefix = ""
    )

    # Use default template path if not specified
    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "ConditionalAccess"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        throw "Conditional Access template directory not found: $TemplatePath"
    }

    # Get all CA policy templates
    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File

    if ($templateFiles.Count -eq 0) {
        Write-Warning "No Conditional Access templates found in: $TemplatePath"
        return @()
    }

    Write-Information "Found $($templateFiles.Count) Conditional Access policy templates" -InformationAction Continue

    $results = @()

    foreach ($templateFile in $templateFiles) {
        $policyName = [System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name)
        $displayName = "$Prefix$policyName"

        try {
            # Load template
            $templateContent = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8
            $policy = $templateContent | ConvertFrom-Json

            # Check if policy already exists
            $existingPolicies = Invoke-MgGraphRequest -Method GET -Uri "v1.0/identity/conditionalAccess/policies?`$filter=displayName eq '$displayName'" -ErrorAction Stop

            if ($existingPolicies.value.Count -gt 0) {
                Write-Information "Policy already exists: $displayName" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Id $existingPolicies.value[0].id -Action 'Skipped' -Status 'Already exists' -State $existingPolicies.value[0].state
                continue
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create Conditional Access policy (disabled)")) {
                # Build the policy body - force state to disabled
                $policyBody = @{
                    displayName = $displayName
                    state = "disabled"  # Always disabled for safety
                    conditions = $policy.conditions
                    grantControls = $policy.grantControls
                }

                # Add session controls if present
                if ($policy.sessionControls) {
                    $policyBody.sessionControls = $policy.sessionControls
                }

                # Remove any odata context properties that shouldn't be in create request
                $jsonBody = $policyBody | ConvertTo-Json -Depth 20
                $jsonBody = $jsonBody -replace '"@odata\.[^"]*":\s*"[^"]*",?\s*', ''
                $jsonBody = $jsonBody -replace '"@odata\.[^"]*":\s*null,?\s*', ''

                # Create the policy
                $newPolicy = Invoke-MgGraphRequest -Method POST -Uri "v1.0/identity/conditionalAccess/policies" -Body $jsonBody -ContentType "application/json" -ErrorAction Stop

                Write-Information "Created policy: $displayName (ID: $($newPolicy.id)) - DISABLED" -InformationAction Continue

                $results += New-HydrationResult -Name $displayName -Id $newPolicy.id -Action 'Created' -Status 'Success' -State 'disabled'
            }
            else {
                $results += New-HydrationResult -Name $displayName -Action 'WouldCreate' -Status 'DryRun' -State 'disabled'
            }
        }
        catch {
            Write-Error "Failed to create policy '$displayName': $_"
            $results += New-HydrationResult -Name $displayName -Action 'Failed' -Status $_.Exception.Message
        }
    }

    # Summary
    $summary = Get-ResultSummary -Results $results

    Write-Information "Conditional Access import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue
    Write-Information "IMPORTANT: All policies were created in DISABLED state. Review and enable as needed." -InformationAction Continue

    return $results
}

function Get-HydrationSummary {
    <#
    .SYNOPSIS
        Generates hydration summary report
    .DESCRIPTION
        Creates a summary of all operations performed during hydration
    .PARAMETER OutputPath
        Path to write the summary report
    .PARAMETER Format
        Output format (markdown, json, csv)
    .EXAMPLE
        Get-HydrationSummary -OutputPath ./Reports -Format markdown
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputPath = "./Reports",

        [Parameter()]
        [ValidateSet('markdown', 'json', 'csv')]
        [string[]]$Format = @('markdown')
    )

    # TODO: Implement summary generation
    throw [System.NotImplementedException]::new("Get-HydrationSummary not yet implemented")
}

# Export functions
Export-ModuleMember -Function $publicFunctions
