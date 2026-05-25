#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Utilities/Get-ConfigurationSection.ps1
}

Describe 'Get-ConfigurationSection' {
    It 'Should return an existing non-null section' {
        $section = @{ Name = 'Contoso' }
        $result = Get-ConfigurationSection -InputObject @{ Information = $section } -Name 'Information'

        $result | Should -Be $section
    }

    It 'Should return an empty hashtable when the section is missing' {
        $result = Get-ConfigurationSection -InputObject @{} -Name 'Information'

        $result | Should -BeOfType ([hashtable])
        $result.Count | Should -Be 0
    }

    It 'Should return an empty hashtable when the section is explicitly null' {
        $result = Get-ConfigurationSection -InputObject @{ Information = $null } -Name 'Information'

        $result | Should -BeOfType ([hashtable])
        $result.Count | Should -Be 0
    }
}
