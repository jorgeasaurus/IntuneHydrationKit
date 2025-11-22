function Test-IntunePrerequisites {
    <#
    .SYNOPSIS
        Checks if all prerequisites are met
    
    .DESCRIPTION
        Validates PowerShell version, required modules, internet connectivity, and Git installation
    
    .OUTPUTS
        Boolean indicating whether prerequisites are met
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-IntuneLog "Checking prerequisites..." -Level INFO
    
    # Check PowerShell version
    if (($PSVersionTable.PSVersion.Major -lt 5) -or 
        (($PSVersionTable.PSVersion.Major -eq 5) -and ($PSVersionTable.PSVersion.Minor -lt 1))) {
        Write-IntuneLog "PowerShell 5.1 or higher is required. Current version: $($PSVersionTable.PSVersion)" -Level ERROR
        return $false
    }
    
    Write-IntuneLog "PowerShell version: $($PSVersionTable.PSVersion)" -Level INFO
    
    # Check for Git
    try {
        $gitCommand = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitCommand) {
            Write-IntuneLog "Git is not installed or not in PATH. Please install Git to clone repositories." -Level ERROR
            return $false
        }
        Write-IntuneLog "Git is installed" -Level INFO
    }
    catch {
        Write-IntuneLog "Git is not installed or not in PATH. Please install Git to clone repositories." -Level ERROR
        return $false
    }
    
    # Check and install required modules
    foreach ($moduleName in $Script:RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            Write-IntuneLog "Module $moduleName is not installed. Attempting to install..." -Level WARNING
            try {
                Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                Write-IntuneLog "Successfully installed $moduleName" -Level SUCCESS
            }
            catch {
                Write-IntuneLog "Failed to install $moduleName : $_" -Level ERROR
                return $false
            }
        }
        else {
            Write-IntuneLog "Module $moduleName is already installed" -Level INFO
        }
    }
    
    # Check internet connectivity
    try {
        $null = Test-Connection -ComputerName "graph.microsoft.com" -Count 1 -Quiet -ErrorAction Stop
        Write-IntuneLog "Internet connectivity verified" -Level SUCCESS
    }
    catch {
        Write-IntuneLog "Internet connectivity test failed. Please check your connection." -Level ERROR
        return $false
    }
    
    # Create temp directory
    if (-not (Test-Path $Script:TempPath)) {
        New-Item -Path $Script:TempPath -ItemType Directory -Force | Out-Null
        Write-IntuneLog "Created temporary directory: $Script:TempPath" -Level INFO
    }
    
    return $true
}
