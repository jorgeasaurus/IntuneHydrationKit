function Deduplicate-HydrationDeleteCandidates {
    <#
    .SYNOPSIS
        Deduplicates delete candidate objects by name.
    .DESCRIPTION
        Removes duplicate delete candidate entries, keeping the first occurrence of each unique name.
        Useful when multiple delete endpoints or queries may return the same resource.
    .PARAMETER Candidates
        Array of delete candidate objects with Name and Id properties.
    .EXAMPLE
        $deduped = Deduplicate-HydrationDeleteCandidates -Candidates $deleteCandidates

        Returns only the first entry for each unique Name.
    .OUTPUTS
        hashtable[] containing deduplicated Name, Id, and Url for batch delete operations.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Candidates
    )

    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $deduplicated = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($candidate in $Candidates) {
        if ($seenNames.Add([string]$candidate.Name)) {
            $deduplicated.Add($candidate)
        }
    }

    return @($deduplicated)
}
