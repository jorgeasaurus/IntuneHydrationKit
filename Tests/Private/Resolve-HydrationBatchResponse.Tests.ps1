#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Graph/Resolve-HydrationBatchResponse.ps1

    function New-TestBatchEntry {
        param(
            [Parameter(Mandatory)]
            [object]$Request,

            [Parameter(Mandatory)]
            [object]$Item,

            [Parameter(Mandatory)]
            [int]$Index
        )

        return [pscustomobject]@{
            Id      = [string]$Request.id
            Request = $Request
            Item    = $Item
            Index   = $Index
        }
    }
}

Describe 'Resolve-HydrationBatchResponse' {
    It 'Should map response ids to items and expose missing requests' {
        $items = @(
            [pscustomobject]@{ Name = 'One' }
            [pscustomobject]@{ Name = 'Two' }
        )
        $requests = @(
            @{ id = '1'; method = 'POST'; url = '/groups' }
            @{ id = '2'; method = 'POST'; url = '/groups' }
        )
        $entries = @(
            New-TestBatchEntry -Request $requests[0] -Item $items[0] -Index 0
            New-TestBatchEntry -Request $requests[1] -Item $items[1] -Index 1
        )
        $responses = @(
            [pscustomobject]@{ id = '1'; status = 201 }
        )

        $state = Resolve-HydrationBatchResponse -BatchEntries $entries -Responses $responses

        $state.Matched[0].Item.Name | Should -Be 'One'
        $state.Missing | Should -HaveCount 1
        $state.Missing[0].Item.Name | Should -Be 'Two'
        $state.Unmatched | Should -BeNullOrEmpty
    }

    It 'Should leave nonnumeric response ids unmatched and keep valid requests missing' {
        $items = @(
            [pscustomobject]@{ Name = 'One' }
        )
        $requests = @(
            @{ id = '1'; method = 'POST'; url = '/groups' }
        )
        $entries = @(
            New-TestBatchEntry -Request $requests[0] -Item $items[0] -Index 0
        )
        $responses = @(
            [pscustomobject]@{ id = 'abc'; status = 201 }
        )

        $state = Resolve-HydrationBatchResponse -BatchEntries $entries -Responses $responses

        $state.Unmatched | Should -HaveCount 1
        $state.Unmatched[0].Item | Should -BeNullOrEmpty
        $state.Missing | Should -HaveCount 1
        $state.Missing[0].Item.Name | Should -Be 'One'
    }

    It 'Should leave unknown response ids unmatched and keep valid requests missing' {
        $items = @(
            [pscustomobject]@{ Name = 'One' }
        )
        $requests = @(
            @{ id = '1'; method = 'POST'; url = '/groups' }
        )
        $entries = @(
            New-TestBatchEntry -Request $requests[0] -Item $items[0] -Index 0
        )
        $responses = @(
            [pscustomobject]@{ id = '99'; status = 201 }
        )

        $state = Resolve-HydrationBatchResponse -BatchEntries $entries -Responses $responses

        $state.Unmatched[0].Item | Should -BeNullOrEmpty
        $state.Missing | Should -HaveCount 1
        $state.Missing[0].Item.Name | Should -Be 'One'
    }

}
