function Get-IntuneWinUploadChunkLength {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int64]::MaxValue)]
        [int64]$FileSize,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$ChunkIndex,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ChunkSizeBytes
    )

    $chunkSize = [int64]$ChunkSizeBytes
    $chunkOffset = [int64]$ChunkIndex * $chunkSize
    if ($chunkOffset -ge $FileSize) {
        return 0
    }

    return [int][Math]::Min($chunkSize, $FileSize - $chunkOffset)
}
