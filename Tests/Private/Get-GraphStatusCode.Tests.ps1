#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Get-GraphStatusCode.ps1
}

Describe 'Get-GraphStatusCode' {
    It 'Should read ResponseStatusCode when present' {
        $exception = [System.Exception]::new('Graph error')
        $exception | Add-Member -NotePropertyName 'ResponseStatusCode' -NotePropertyValue 404 -Force
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)

        (Get-GraphStatusCode -ErrorRecord $errorRecord) | Should -Be 404
    }

    It 'Should read StatusCode when present on the exception' {
        $exception = [System.Exception]::new('Graph error')
        $exception | Add-Member -NotePropertyName 'StatusCode' -NotePropertyValue ([System.Net.HttpStatusCode]::Forbidden) -Force
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)

        (Get-GraphStatusCode -ErrorRecord $errorRecord) | Should -Be 403
    }

    It 'Should read nested Response.StatusCode when present' {
        $exception = [System.Exception]::new('Graph error')
        $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue ([PSCustomObject]@{
                StatusCode = [System.Net.HttpStatusCode]::TooManyRequests
            }) -Force
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)

        (Get-GraphStatusCode -ErrorRecord $errorRecord) | Should -Be 429
    }

    It 'Should return null when no status code is available' {
        $exception = [System.Exception]::new('Graph error')
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'TestError', 'NotSpecified', $null)

        $result = Get-GraphStatusCode -ErrorRecord $errorRecord

        $null -eq $result | Should -Be $true
    }
}
