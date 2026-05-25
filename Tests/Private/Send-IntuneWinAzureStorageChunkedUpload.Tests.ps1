#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/WinGet/Get-IntuneWinUploadChunkLength.ps1
    . $PSScriptRoot/../../Private/WinGet/Invoke-IntuneWinAzureStorageBlockUpload.ps1
    . $PSScriptRoot/../../Private/WinGet/Send-IntuneWinAzureStorageChunkedUpload.ps1
}

Describe 'Send-IntuneWinAzureStorageChunkedUpload' {
    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "IntuneWinUpload-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -Path $script:testRoot -ItemType Directory -Force
        $script:testFile = Join-Path $script:testRoot 'payload.bin'
        [System.IO.File]::WriteAllBytes($script:testFile, [byte[]](1, 2, 3, 4, 5))
        $script:uploadedBodies = [System.Collections.Generic.List[object]]::new()

        Mock Invoke-IntuneWinAzureStorageBlockUpload {
            param($Uri, [byte[]]$Body)

            $null = $Uri
            $script:uploadedBodies.Add($Body)
            return @{ StatusCode = 201 }
        }

        Mock Invoke-RestMethod { return @{} }
    }

    AfterEach {
        if (Test-Path -Path $script:testRoot) {
            Remove-Item -Path $script:testRoot -Recurse -Force
        }
    }

    It 'Should delegate each chunk to the typed block upload helper' {
        $result = Send-IntuneWinAzureStorageChunkedUpload -FilePath $script:testFile -UploadUri 'https://storage.example.test/container/blob?sig=test' -ChunkSizeBytes 3

        $result.ChunkCount | Should -Be 2
        Should -Invoke Invoke-IntuneWinAzureStorageBlockUpload -Exactly 2
        Should -Invoke Invoke-RestMethod -Exactly 1
    }

    It 'Should define the block upload body as raw bytes' {
        (Get-Command Invoke-IntuneWinAzureStorageBlockUpload).Parameters['Body'].ParameterType | Should -Be ([byte[]])
    }
}
