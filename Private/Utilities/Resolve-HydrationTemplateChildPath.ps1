function Resolve-HydrationTemplateChildPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$ChildPath,

        [Parameter()]
        [string]$PathLabel = 'Template child path'
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
    $candidatePath = Join-Path -Path $resolvedRoot -ChildPath $ChildPath
    $resolvedChildPath = (Resolve-Path -LiteralPath $candidatePath -ErrorAction Stop).Path
    $rootPrefix = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    if ($resolvedChildPath -ne $resolvedRoot -and -not $resolvedChildPath.StartsWith($rootPrefix, $pathComparison)) {
        throw "$PathLabel '$ChildPath' resolves outside template root '$RootPath'."
    }

    return $resolvedChildPath
}
