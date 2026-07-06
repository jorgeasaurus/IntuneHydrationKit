function Resolve-HydrationDeleteDecision {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Notes,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [System.Collections.Generic.HashSet[string]]$KnownTemplateNames,

        [Parameter()]
        [switch]$NameOnly,

        [Parameter()]
        [switch]$MobileAppName,

        [Parameter()]
        [switch]$RequireOwnership,

        [Parameter()]
        [bool]$IsOwned = $true,

        [Parameter()]
        [string]$OwnershipFailureMessage = 'not created by Intune Hydration Kit'
    )

    function New-Decision {
        param([bool]$IsMatch, [bool]$NeedsFullObject, [string]$Reason, [string]$Message, [bool]$MatchesTemplateName)
        return [pscustomobject]@{
            IsMatch             = $IsMatch
            NeedsFullObject     = $NeedsFullObject
            Reason              = $Reason
            Message             = $Message
            MatchesTemplateName = $MatchesTemplateName
        }
    }

    $hasTemplateNames = $KnownTemplateNames -and $KnownTemplateNames.Count -gt 0
    if (-not $hasTemplateNames) {
        return New-Decision $false $false 'TemplateNameSetMissing' 'template names are required for safe deletion' $false
    }

    $matchesTemplateName = if ($MobileAppName) {
        Test-HydrationMobileAppNameInSet -DisplayName $Name -NameSet $KnownTemplateNames
    } else {
        Test-HydrationTemplateNameMatch -Name $Name -KnownTemplateNames $KnownTemplateNames
    }

    if (-not $matchesTemplateName) {
        return New-Decision $false $false 'TemplateNameNotInScope' 'not in current template set' $false
    }

    if ($NameOnly) {
        return New-Decision $true $false 'Delete' 'matched hydration delete scope' $true
    }

    if ($RequireOwnership) {
        if (-not $IsOwned) {
            return New-Decision $false $false 'NotHydrationKitObject' $OwnershipFailureMessage $true
        }

        return New-Decision $true $false 'Delete' 'matched hydration delete scope' $true
    }

    $hasMarkerFields = -not [string]::IsNullOrWhiteSpace($Description) -or -not [string]::IsNullOrWhiteSpace($Notes)
    if (-not $hasMarkerFields) {
        return New-Decision $false $true 'NeedsMarkerVerification' 'requires full object marker verification' $true
    }

    if (-not (Test-HydrationKitObject -Description $Description -Notes $Notes -ObjectName $Name)) {
        return New-Decision $false $false 'NotHydrationKitObject' $OwnershipFailureMessage $true
    }

    return New-Decision $true $false 'Delete' 'matched hydration delete scope' $true
}
