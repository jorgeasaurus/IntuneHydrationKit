function Resolve-WinGetAppIcon {
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template
    )

    function Get-IconMimeType {
        param(
            [Parameter()]
            [string]$Path
        )

        $extension = [System.IO.Path]::GetExtension($Path)
        switch ($extension.ToLowerInvariant()) {
            '.png' { return 'image/png' }
            '.jpg' { return 'image/jpeg' }
            '.jpeg' { return 'image/jpeg' }
            '.gif' { return 'image/gif' }
            '.bmp' { return 'image/bmp' }
            '.ico' { return 'image/x-icon' }
            '.svg' { return 'image/svg+xml' }
            default { return 'image/png' }
        }
    }

    function Get-BytesFromFile {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        $resolvedPath = $Path
        if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
            $templateDirectory = Split-Path -Path ([string]$Template.TemplatePath) -Parent
            if (-not [string]::IsNullOrWhiteSpace($templateDirectory)) {
                $resolvedPath = Join-Path -Path $templateDirectory -ChildPath $resolvedPath
            }
        }

        if (-not (Test-Path -Path $resolvedPath -PathType Leaf)) {
            throw "Icon file not found: $resolvedPath"
        }

        return [PSCustomObject]@{
            Bytes    = [System.IO.File]::ReadAllBytes($resolvedPath)
            MimeType = Get-IconMimeType -Path $resolvedPath
            Source   = $resolvedPath
        }
    }

    function Get-BundledFallbackIcon {
        $fallbackIconPath = Join-Path -Path $script:ModuleRoot -ChildPath 'media/IHKLogoClearLight.png'
        if (-not (Test-Path -Path $fallbackIconPath -PathType Leaf)) {
            Write-Debug "Bundled fallback icon not found at '$fallbackIconPath'."
            return $null
        }

        Write-Debug "Using bundled fallback icon at '$fallbackIconPath'."
        return [PSCustomObject]@{
            Bytes    = [System.IO.File]::ReadAllBytes($fallbackIconPath)
            MimeType = Get-IconMimeType -Path $fallbackIconPath
            Source   = $fallbackIconPath
        }
    }

    if (-not $Template.PSObject.Properties.Name.Contains('icon') -or $null -eq $Template.icon) {
        Write-Debug "No icon property was configured for WinGet template '$($Template.templateId)'. Falling back to bundled icon."
        $iconConfig = [pscustomobject]@{}
        $sourceType = 'none'
    } else {
        $iconConfig = $Template.icon
        $sourceType = [string]$iconConfig.sourceType
    }
    if ([string]::IsNullOrWhiteSpace($sourceType) -or $sourceType -eq 'none') {
        Write-Debug "No icon configured for WinGet template '$($Template.templateId)'. Falling back to bundled icon."
        $sourceType = 'none'
    }

    $iconResult = switch ($sourceType) {
        'file' {
            $filePath = [string]$iconConfig.fileName

            if ([string]::IsNullOrWhiteSpace($filePath)) {
                Write-Debug "Template '$($Template.templateId)' specifies icon.sourceType='file' but icon.fileName is not set."
                $null
            } else {
                try {
                    Get-BytesFromFile -Path $filePath
                } catch {
                    Write-Debug "Failed to resolve template icon file for '$($Template.templateId)': $($_.Exception.Message)"
                    $null
                }
            }
        }
        default {
            Write-Debug "Unsupported icon source type '$sourceType' for template '$($Template.templateId)'."
            $null
        }
    }

    if ($null -eq $iconResult) {
        $iconResult = Get-BundledFallbackIcon
    }

    if ($null -eq $iconResult -or $null -eq $iconResult.Bytes -or $iconResult.Bytes.Length -eq 0) {
        return $null
    }

    Write-Debug "Resolved icon for WinGet template '$($Template.templateId)' from '$($iconResult.Source)' with MimeType='$($iconResult.MimeType)'."
    return [PSCustomObject]@{
        Base64   = [System.Convert]::ToBase64String($iconResult.Bytes)
        MimeType = $iconResult.MimeType
        Source   = $iconResult.Source
    }
}
