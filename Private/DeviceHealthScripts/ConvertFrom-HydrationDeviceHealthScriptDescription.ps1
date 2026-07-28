function ConvertFrom-HydrationDeviceHealthScriptDescription {
    <#
    .SYNOPSIS
        Parses newline-delimited device health script metadata.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, string]])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Description
    )

    $metadata = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $Description -split "`r?`n") {
        $separatorIndex = $line.IndexOf(':')
        if ($separatorIndex -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separatorIndex).Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $metadata[$key] = $line.Substring($separatorIndex + 1).Trim()
        }
    }

    return $metadata
}
