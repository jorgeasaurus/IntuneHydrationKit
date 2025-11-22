function Get-IntuneGitHubRepository {
    <#
    .SYNOPSIS
        Clones or updates a GitHub repository
    
    .DESCRIPTION
        Internal helper function to clone or update GitHub repositories
    
    .PARAMETER RepositoryUrl
        The URL of the GitHub repository
    
    .PARAMETER DestinationPath
        The local path where the repository should be cloned
    
    .OUTPUTS
        Boolean indicating success or failure
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepositoryUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )
    
    Write-IntuneLog "Fetching repository: $RepositoryUrl" -Level INFO
    
    try {
        if (Test-Path $DestinationPath) {
            Write-IntuneLog "Repository already exists at $DestinationPath. Updating..." -Level INFO
            Push-Location $DestinationPath
            try {
                # Try to pull from the default branch
                $gitOutput = git pull 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-IntuneLog "Git pull failed: $gitOutput" -Level WARNING
                    Write-IntuneLog "Repository may be out of sync, but will proceed with existing content" -Level WARNING
                }
            }
            catch {
                Write-IntuneLog "Error during git pull: $_" -Level WARNING
                Write-IntuneLog "Will proceed with existing repository content" -Level WARNING
            }
            finally {
                Pop-Location
            }
        }
        else {
            Write-IntuneLog "Cloning repository to $DestinationPath..." -Level INFO
            $gitOutput = git clone $RepositoryUrl $DestinationPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-IntuneLog "Git clone failed: $gitOutput" -Level ERROR
                return $false
            }
        }
        
        if (Test-Path $DestinationPath) {
            Write-IntuneLog "Repository ready at $DestinationPath" -Level SUCCESS
            return $true
        }
        else {
            Write-IntuneLog "Failed to clone repository" -Level ERROR
            return $false
        }
    }
    catch {
        Write-IntuneLog "Error accessing repository: $_" -Level ERROR
        return $false
    }
}
