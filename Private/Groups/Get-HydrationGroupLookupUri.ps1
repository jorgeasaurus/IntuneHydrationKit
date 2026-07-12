function Get-HydrationGroupLookupUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$GroupDefinition
    )

    $safePrefixedName = $GroupDefinition.displayName -replace "'", "''"
    $safeOriginalName = $GroupDefinition._OriginalDisplayName -replace "'", "''"

    if ($safePrefixedName -ne $safeOriginalName) {
        return "/groups?`$filter=displayName eq '$safePrefixedName' or displayName eq '$safeOriginalName'&`$select=id,displayName,description"
    }

    return "/groups?`$filter=displayName eq '$safePrefixedName'&`$select=id,displayName,description"
}
