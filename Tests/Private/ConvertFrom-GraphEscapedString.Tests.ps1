#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Graph/ConvertFrom-GraphEscapedString.ps1
}

Describe 'ConvertFrom-GraphEscapedString' {
    It 'Should collapse escaped backslashes in non-nested messages' {
        $result = ConvertFrom-GraphEscapedString -Value 'Path C:\\Temp\\App'

        $result | Should -Be 'Path C:\Temp\App'
    }

    It 'Should preserve escaped backslashes for nested messages' {
        $result = ConvertFrom-GraphEscapedString -Value 'Path C:\\Temp\\App' -NestedMessage

        $result | Should -Be 'Path C:\\Temp\\App'
    }
}
