function Get-TemplateFiles {
    <#
    .SYNOPSIS
        Gets all JSON template files from a directory
    .PARAMETER Path
        Path to the template directory
    .PARAMETER Recurse
        Search subdirectories
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path,

        [Parameter()]
        [switch]$Recurse
    )

    $params = @{
        Path = $Path
        Filter = "*.json"
        File = $true
    }

    if ($Recurse) {
        $params['Recurse'] = $true
    }

    Get-ChildItem @params
}
