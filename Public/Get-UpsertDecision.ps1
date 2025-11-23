function Get-UpsertDecision {
    <#
    .SYNOPSIS
        Determines whether to create, update, or skip a resource
    .PARAMETER ExistingResource
        The existing resource (if any)
    .PARAMETER NewResource
        The new resource definition
    .PARAMETER ForceUpdate
        Force update even if no changes detected
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$ExistingResource,

        [Parameter(Mandatory = $true)]
        [object]$NewResource,

        [Parameter()]
        [switch]$ForceUpdate
    )

    if (-not $ExistingResource) {
        return @{
            Action = 'Create'
            Reason = 'Resource does not exist'
        }
    }

    if ($ForceUpdate) {
        return @{
            Action = 'Update'
            Reason = 'Force update requested'
            ExistingId = $ExistingResource.id
        }
    }

    # Compare resources (simplified - could be enhanced for deep comparison)
    $existingJson = $ExistingResource | ConvertTo-Json -Depth 10 -Compress
    $newJson = $NewResource | ConvertTo-Json -Depth 10 -Compress

    if ($existingJson -ne $newJson) {
        return @{
            Action = 'Update'
            Reason = 'Resource has changed'
            ExistingId = $ExistingResource.id
        }
    }

    return @{
        Action = 'Skip'
        Reason = 'Resource is up to date'
        ExistingId = $ExistingResource.id
    }
}
