function Resolve-HydrationTuiOptionSelection {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Options,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Selection,

        [Parameter()]
        [switch]$AllowAllKeyword
    )

    $tokens = @($Selection -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($tokens.Count -eq 0) {
        return @()
    }

    $selectedOptions = [System.Collections.Generic.List[object]]::new()
    $selectedNumbers = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($token in $tokens) {
        $trimmedToken = $token.Trim()

        if ($AllowAllKeyword -and $trimmedToken.Equals('all', [System.StringComparison]::OrdinalIgnoreCase)) {
            $match = $Options | Where-Object { $_.IsExclusive } | Select-Object -First 1
            if (-not $match) {
                throw "Invalid selection '$token'. Enter option numbers separated by commas."
            }
        } else {
            $number = 0
            if (-not [int]::TryParse($trimmedToken, [ref]$number)) {
                throw "Invalid selection '$token'. Enter option numbers separated by commas."
            }

            $match = $Options | Where-Object { $_.Number -eq $number } | Select-Object -First 1
            if (-not $match) {
                throw "Invalid option number '$number'."
            }
        }

        if ($selectedNumbers.Add($match.Number)) {
            $selectedOptions.Add($match)
        }
    }

    return $selectedOptions.ToArray()
}
