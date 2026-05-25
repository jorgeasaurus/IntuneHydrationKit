function ConvertTo-HydrationBoolValue {
    <#
    .SYNOPSIS
        Normalizes an input value to a boolean.
    .DESCRIPTION
        Converts common string representations ('true', '1', 'yes', 'false', '0', 'no')
        and raw booleans into a proper [bool]. Null values return $false.
    .PARAMETER Value
        The value to convert.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return $Value
    }

    $normalizedValue = ([string]$Value).Trim()
    switch -Regex ($normalizedValue) {
        '^(?i:true|1|yes)$' { return $true }
        '^(?i:false|0|no)$' { return $false }
        default {
            if ($Value -is [string]) {
                throw "Unsupported boolean string value: '$Value'"
            }

            return [bool]$Value
        }
    }
}
