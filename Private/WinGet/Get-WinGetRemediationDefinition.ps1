function Get-WinGetRemediationDefinition {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('system', 'user')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [psobject[]]$TemplateSet
    )

    $packageScope = if ($Scope -eq 'system') { 'machine' } else { 'user' }
    $packageIdentifiers = @(
        $TemplateSet |
            Where-Object { [string]$_.package.match.scope -eq $packageScope } |
            ForEach-Object { [string]$_.packageIdentifier } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    return [PSCustomObject]@{
        Scope              = $Scope
        DisplayName        = "WinGet App Updates ($([cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($Scope)))"
        RunAsAccount       = if ($Scope -eq 'system') { 'system' } else { 'user' }
        PackageIdentifiers = $packageIdentifiers
        Description        = if ($packageIdentifiers.Count -gt 0) { New-WinGetRemediationDescription -Scope $Scope -PackageIdentifiers $packageIdentifiers } else { $null }
    }
}
