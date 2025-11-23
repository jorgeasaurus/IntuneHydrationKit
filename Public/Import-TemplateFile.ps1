function Import-TemplateFile {
    <#
    .SYNOPSIS
        Imports and parses a JSON template file
    .PARAMETER Path
        Path to the template file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path
    )

    try {
        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $template = $content | ConvertFrom-Json -AsHashtable

        Write-HydrationLog -Message "Loaded template: $Path" -Level Debug
        return $template
    }
    catch {
        Write-HydrationLog -Message "Failed to load template: $Path - $_" -Level Error
        throw
    }
}
