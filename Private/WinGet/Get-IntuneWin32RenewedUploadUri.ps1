function Get-IntuneWin32RenewedUploadUri {
    <#
    .SYNOPSIS
        Renews the Azure Storage upload URI for a Win32 content file.
    .PARAMETER AppId
        Target Intune app identifier.
    .PARAMETER ContentVersionId
        Content version identifier.
    .PARAMETER ContentFileId
        Content file identifier.
    .PARAMETER ContentFileUri
        Base Graph URI for content files under the content version.
    .PARAMETER TimeoutSeconds
        Timeout used when waiting for renewal success state.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$ContentVersionId,

        [Parameter(Mandatory)]
        [string]$ContentFileId,

        [Parameter(Mandatory)]
        [string]$ContentFileUri,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    Write-Debug "Renewing Azure Storage upload URI for content file '$ContentFileId'."
    Invoke-HydrationGraphRequest -Method POST -Uri "$ContentFileUri/$ContentFileId/renewUpload" -Body @{} | Out-Null

    $renewedFileInfo = Wait-IntuneWin32ContentState -AppId $AppId -ContentVersionId $ContentVersionId -FileId $ContentFileId -DesiredState 'azureStorageUriRenewalSuccess' -TimeoutSeconds $TimeoutSeconds
    return $renewedFileInfo.azureStorageUri
}
