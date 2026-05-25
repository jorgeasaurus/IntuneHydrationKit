function Test-IsWinGetTemplateFile {
    <#
    .SYNOPSIS
        Tests whether a template file resides under a WinGet directory.
    .DESCRIPTION
        Walks up the directory tree from the template file to detect if any
        parent directory is named 'WinGet'. Used to exclude WinGet-backed
        templates from the generic mobile app import path.
    .PARAMETER TemplateFile
        The FileInfo object representing the template file to test.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$TemplateFile
    )

    $currentPath = $TemplateFile.DirectoryName
    while (-not [string]::IsNullOrWhiteSpace($currentPath)) {
        if ((Split-Path -Path $currentPath -Leaf) -eq 'WinGet') {
            return $true
        }

        $parentPath = Split-Path -Path $currentPath -Parent
        if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $currentPath) {
            break
        }

        $currentPath = $parentPath
    }

    return $false
}
