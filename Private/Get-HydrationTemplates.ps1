function Get-HydrationTemplates {
    <#
    .SYNOPSIS
        Gets template files from a directory
    .DESCRIPTION
        Internal helper function that retrieves JSON template files from a specified path.
    .PARAMETER Path
        The directory path to search for template files
    .PARAMETER Recurse
        If specified, searches subdirectories recursively
    .PARAMETER ResourceType
        The type of resource being loaded (for logging purposes)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [string]$ResourceType = "template"
    )

    $templates = Get-ChildItem -Path $Path -Filter "*.json" -File -Recurse:$Recurse

    Write-Verbose "Found $($templates.Count) $ResourceType template(s) in $Path"

    return $templates
}
