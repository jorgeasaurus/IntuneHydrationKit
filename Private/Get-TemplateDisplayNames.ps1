function Get-TemplateDisplayNames {
    <#
    .SYNOPSIS
        Extracts display names from template JSON files into a lookup hashtable.
    .DESCRIPTION
        Loads JSON template files from a directory and extracts display names using the
        appropriate property for each resource type. Returns a case-insensitive hashtable
        of known template names for use as a safety gate in delete operations.
    .PARAMETER Path
        The directory path containing template JSON files.
    .PARAMETER NameProperty
        The JSON property to extract as the display name. Defaults to 'displayName'.
        Use 'name' for resources that use the name property (e.g., configurationPolicies).
    .PARAMETER ArrayProperty
        If templates contain a nested array of objects (e.g., 'filters' or 'groups'),
        specify the array property name. Names will be extracted from each array element.
    .PARAMETER Recurse
        If specified, searches subdirectories recursively.
    .PARAMETER UseFileName
        If specified, uses the file basename (without extension) as the name instead of
        a JSON property. Used for Conditional Access templates.
    .PARAMETER Prefix
        Optional prefix to prepend to each name. Used for Conditional Access templates
        that add a prefix to file basenames.
    .OUTPUTS
        [hashtable] Case-insensitive hashtable where keys are display names and values are $true.
    .EXAMPLE
        Get-TemplateDisplayNames -Path './Templates/MobileApps' -Recurse
    .EXAMPLE
        Get-TemplateDisplayNames -Path './Templates/Filters' -ArrayProperty 'filters' -Recurse
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$NameProperty = 'displayName',

        [Parameter()]
        [string]$ArrayProperty,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [switch]$UseFileName,

        [Parameter()]
        [string]$Prefix
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (-not (Test-Path -Path $Path)) {
        Write-Verbose "Template path not found: $Path"
        return , $names
    }

    $templateFiles = Get-ChildItem -Path $Path -Filter "*.json" -File -Recurse:$Recurse

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Verbose "No template files found in: $Path"
        return , $names
    }

    foreach ($file in $templateFiles) {
        if ($UseFileName) {
            $name = "$Prefix$([System.IO.Path]::GetFileNameWithoutExtension($file.Name))"
            [void]$names.Add($name)
            continue
        }

        try {
            $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Verbose "Failed to parse template: $($file.Name)"
            continue
        }

        if ($ArrayProperty -and $content.$ArrayProperty) {
            foreach ($item in $content.$ArrayProperty) {
                $itemName = $item.$NameProperty
                if ($itemName) {
                    [void]$names.Add($itemName)
                }
            }
        } else {
            $name = $content.$NameProperty
            if (-not $name -and $NameProperty -eq 'displayName') {
                $name = $content.name
            }
            if ($name) {
                [void]$names.Add($name)
            }
        }
    }

    Write-Verbose "Loaded $($names.Count) template name(s) from $Path"

    # Comma operator prevents PowerShell from enumerating the HashSet on output.
    # Without it, an empty HashSet is enumerated to nothing and the caller gets $null.
    return , $names
}
