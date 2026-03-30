function New-HydrationDescription {
    <#
    .SYNOPSIS
        Builds a description or notes string with the hydration kit tag appended
    .DESCRIPTION
        Appends "Imported by Intune Hydration Kit" to an existing description string,
        separated by " - " if existing text is present. Used across all import functions
        to consistently tag created objects.
    .PARAMETER ExistingText
        The existing description or notes text. If empty or null, returns just the tag.
    .PARAMETER Separator
        The separator between existing text and the hydration tag. Defaults to ' - '.
        Use ' ' for resource types that reject special characters (e.g., Autopilot profiles).
    .EXAMPLE
        New-HydrationDescription
        # Returns: "Imported by Intune Hydration Kit"
    .EXAMPLE
        New-HydrationDescription -ExistingText "My policy description"
        # Returns: "My policy description - Imported by Intune Hydration Kit"
    .EXAMPLE
        New-HydrationDescription -ExistingText "My profile" -Separator ' '
        # Returns: "My profile Imported by Intune Hydration Kit"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ExistingText,

        [Parameter()]
        [string]$Separator = ' - '
    )

    $tag = 'Imported by Intune Hydration Kit'
    if (-not [string]::IsNullOrWhiteSpace($ExistingText)) {
        return "$ExistingText$Separator$tag"
    }
    return $tag
}
