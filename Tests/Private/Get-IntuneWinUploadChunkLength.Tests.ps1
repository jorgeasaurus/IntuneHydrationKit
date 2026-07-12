#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-IntuneWinUploadChunkLength.ps1
}

Describe 'Get-IntuneWinUploadChunkLength' {
    It 'Should return a full chunk for non-final chunks' {
        Get-IntuneWinUploadChunkLength -FileSize 25 -ChunkIndex 1 -ChunkSizeBytes 10 | Should -Be 10
    }

    It 'Should return the remaining byte count for the final chunk' {
        Get-IntuneWinUploadChunkLength -FileSize 25 -ChunkIndex 2 -ChunkSizeBytes 10 | Should -Be 5
    }

    It 'Should use 64-bit offsets for large packages' {
        $fileSize = [int64]3GB + 123

        Get-IntuneWinUploadChunkLength -FileSize $fileSize -ChunkIndex 512 -ChunkSizeBytes 6MB | Should -Be 123
    }

    It 'Should return zero when the chunk index starts beyond the file' {
        Get-IntuneWinUploadChunkLength -FileSize 25 -ChunkIndex 3 -ChunkSizeBytes 10 | Should -Be 0
    }
}
