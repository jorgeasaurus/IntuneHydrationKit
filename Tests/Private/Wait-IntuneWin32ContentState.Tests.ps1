#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Graph/Invoke-HydrationGraphRequest.ps1
    . $PSScriptRoot/../../Private/WinGet/Wait-IntuneWin32ContentState.ps1
}

Describe 'Wait-IntuneWin32ContentState' {
    BeforeEach {
        Mock Invoke-HydrationGraphRequest {
            [pscustomobject]@{ uploadState = 'commitFileSuccess' }
        }

        Mock Start-Sleep {}
    }

    It 'Should check upload state before sleeping' {
        $result = Wait-IntuneWin32ContentState -AppId 'app-1' -ContentVersionId 'version-1' -FileId 'file-1' -DesiredState 'commitFileSuccess' -PollIntervalSeconds 5 -TimeoutSeconds 10

        $result.uploadState | Should -Be 'commitFileSuccess'
        Should -Invoke Invoke-HydrationGraphRequest -Exactly 1
        Should -Invoke Start-Sleep -Exactly 0
    }

    It 'Should sleep only between unsuccessful polls' {
        $script:pollCount = 0
        Mock Invoke-HydrationGraphRequest {
            $script:pollCount++
            if ($script:pollCount -eq 1) {
                return [pscustomobject]@{ uploadState = 'azureStorageUriRequestPending' }
            }

            [pscustomobject]@{ uploadState = 'azureStorageUriRequestSuccess' }
        }

        $result = Wait-IntuneWin32ContentState -AppId 'app-1' -ContentVersionId 'version-1' -FileId 'file-1' -DesiredState 'azureStorageUriRequestSuccess' -PollIntervalSeconds 5 -TimeoutSeconds 10

        $result.uploadState | Should -Be 'azureStorageUriRequestSuccess'
        Should -Invoke Invoke-HydrationGraphRequest -Exactly 2
        Should -Invoke Start-Sleep -Exactly 1 -ParameterFilter { $Seconds -eq 5 }
    }

    It 'Should cap sleep to the remaining timeout window' {
        Mock Invoke-HydrationGraphRequest {
            [pscustomobject]@{ uploadState = 'azureStorageUriRequestPending' }
        }

        { Wait-IntuneWin32ContentState -AppId 'app-1' -ContentVersionId 'version-1' -FileId 'file-1' -DesiredState 'azureStorageUriRequestSuccess' -PollIntervalSeconds 5 -TimeoutSeconds 2 } |
            Should -Throw "*Timed out waiting for upload state 'azureStorageUriRequestSuccess' for file 'file-1'*"

        Should -Invoke Invoke-HydrationGraphRequest -Exactly 2
        Should -Invoke Start-Sleep -Exactly 1 -ParameterFilter { $Seconds -eq 2 }
    }
}
