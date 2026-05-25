function Send-IntuneWinAzureStorageChunkedUpload {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UploadUri,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ChunkSizeBytes = 6MB,

        [Parameter()]
        [scriptblock]$RenewUploadUri,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ChunkUploadTimeoutSec = 300,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$CommitTimeoutSec = 120
    )

    function Get-UploadUriForLogging {
        param(
            [Parameter(Mandatory)]
            [string]$Uri
        )

        return ($Uri -split '\?', 2)[0]
    }

    $fileSize = [int64](Get-Item -Path $FilePath).Length
    $chunkSize = [int64]$ChunkSizeBytes
    $chunkCount = [int][Math]::Ceiling($fileSize / $chunkSize)
    $currentUploadUri = $UploadUri
    $isoEncoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
    $chunkIds = @()
    Write-Debug "Starting Azure Storage chunked upload for '$FilePath' ($fileSize bytes) to '$(Get-UploadUriForLogging -Uri $UploadUri)' using ChunkSizeBytes=$ChunkSizeBytes across $chunkCount chunk(s)."

    $reader = [System.IO.BinaryReader]::new([System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read))
    try {
        for ($index = 0; $index -lt $chunkCount; $index++) {
            $chunkId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($index.ToString('0000')))
            $chunkIds += $chunkId

            $chunkLength = Get-IntuneWinUploadChunkLength -FileSize $fileSize -ChunkIndex $index -ChunkSizeBytes $ChunkSizeBytes
            $chunkBytes = $reader.ReadBytes($chunkLength)
            $requestBody = $isoEncoding.GetString($chunkBytes)
            $chunkUri = "$currentUploadUri&comp=block&blockid=$chunkId"
            Write-Debug "Uploading Azure Storage chunk $($index + 1)/$chunkCount for '$FilePath' (ChunkId='$chunkId', Bytes=$chunkLength)."

            for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
                try {
                    Invoke-WebRequest -Method PUT -Uri $chunkUri -Body $requestBody -Headers @{
                        'Content-Type'   = 'text/plain; charset=iso-8859-1'
                        'x-ms-blob-type' = 'BlockBlob'
                    } -TimeoutSec $ChunkUploadTimeoutSec -ErrorAction Stop | Out-Null
                    break
                } catch {
                    $isAuthFailure = $_.Exception.Message -match 'AuthenticationFailed|403|authorized'
                    if ($isAuthFailure -and $RenewUploadUri -and $attempt -lt $MaxRetries) {
                        Write-Debug "Azure Storage upload authorization expired for chunk $($index + 1)/$chunkCount. Renewing upload URI before retrying."
                        $currentUploadUri = & $RenewUploadUri
                        $chunkUri = "$currentUploadUri&comp=block&blockid=$chunkId"
                        continue
                    }

                    if ($attempt -eq $MaxRetries) {
                        throw
                    }

                    Write-Debug "Azure Storage upload retry for chunk $($index + 1)/$chunkCount after failure '$($_.Exception.Message)' (attempt $attempt of $MaxRetries)."
                    Start-Sleep -Seconds (5 * $attempt)
                }
            }
        }
    } finally {
        $reader.Close()
        $reader.Dispose()
    }

    $blockListXml = [System.Text.StringBuilder]::new()
    [void]$blockListXml.Append('<?xml version="1.0" encoding="utf-8"?><BlockList>')
    foreach ($chunkId in $chunkIds) {
        [void]$blockListXml.Append("<Latest>$chunkId</Latest>")
    }
    [void]$blockListXml.Append('</BlockList>')
    $blockListBody = $blockListXml.ToString()

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Debug "Committing Azure Storage block list for '$FilePath' with $($chunkIds.Count) chunk(s)."
            Invoke-RestMethod -Method PUT -Uri "$currentUploadUri&comp=blocklist" -Body $blockListBody -Headers @{
                'Content-Type' = 'text/plain; charset=UTF-8'
            } -TimeoutSec $CommitTimeoutSec -ErrorAction Stop | Out-Null
            break
        } catch {
            $isAuthFailure = $_.Exception.Message -match 'AuthenticationFailed|403|authorized'
            if ($isAuthFailure -and $RenewUploadUri -and $attempt -lt $MaxRetries) {
                Write-Debug "Azure Storage block list commit authorization expired. Renewing upload URI before retrying."
                $currentUploadUri = & $RenewUploadUri
                continue
            }

            if ($attempt -eq $MaxRetries) {
                throw
            }

            Write-Debug "Azure Storage block list commit retry after failure '$($_.Exception.Message)' (attempt $attempt of $MaxRetries)."
            Start-Sleep -Seconds (5 * $attempt)
        }
    }

    Write-Debug "Completed Azure Storage chunked upload for '$FilePath'. FinalUploadUri='$(Get-UploadUriForLogging -Uri $currentUploadUri)', ChunkCount=$chunkCount, FileSize=$fileSize."

    return [PSCustomObject]@{
        ChunkCount = $chunkCount
        FileSize   = $fileSize
        UploadUri  = $currentUploadUri
    }
}
