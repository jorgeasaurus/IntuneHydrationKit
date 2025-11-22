#
# IntuneHydrationKit PowerShell Module
# Automates Microsoft Intune tenant configuration with best-practice policies and baselines
#

#region Module Variables

# Module-scoped variables
$Script:LogPath = $null
$Script:LogFile = $null
$Script:OpenIntuneBaselineRepo = "https://github.com/SkipToTheEndpoint/OpenIntuneBaseline"
$Script:IntuneManagementRepo = "https://github.com/Micke-K/IntuneManagement"
$Script:TempPath = $null

# Required PowerShell modules
$Script:RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.DeviceManagement",
    "Microsoft.Graph.Groups",
    "Microsoft.Graph.Identity.SignIns"
)

#endregion

#region Private Functions

# Dot source all private functions
$privateFunctions = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue )
foreach ($import in $privateFunctions) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

#endregion

#region Public Functions

# Dot source all public functions
$publicFunctions = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue )
foreach ($import in $publicFunctions) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function $publicFunctions.BaseName

