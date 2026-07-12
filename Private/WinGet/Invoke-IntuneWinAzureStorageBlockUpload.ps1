function Invoke-IntuneWinAzureStorageBlockUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [byte[]]$Body,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSec = 300
    )

    Invoke-WebRequest -Method PUT -Uri $Uri -Body $Body -Headers @{
        'Content-Type'   = 'application/octet-stream'
        'x-ms-blob-type' = 'BlockBlob'
    } -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null
}
