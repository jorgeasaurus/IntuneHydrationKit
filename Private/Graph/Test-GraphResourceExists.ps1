function Test-GraphResourceExists {
    <#
    .SYNOPSIS
        Tests whether a Graph resource still exists.
    .DESCRIPTION
        Issues a GET against the resource URI. Returns $true on success and
        $false on 404 (handles eventual consistency after deletes). Any other
        error is rethrown.
    .PARAMETER Uri
        Graph resource URI to check.
    .OUTPUTS
        bool
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    try {
        $null = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        return $true
    } catch {
        if ((Get-GraphStatusCode -ErrorRecord $_) -eq 404) {
            return $false
        }
        throw
    }
}
