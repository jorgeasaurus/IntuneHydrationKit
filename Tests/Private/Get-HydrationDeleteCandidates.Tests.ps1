#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot/../../Private/Graph/Get-GraphPagedResults.ps1
    . $PSScriptRoot/../../Private/Hydration/Get-HydrationMarkerSet.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationKitObject.ps1
    . $PSScriptRoot/../../Private/Hydration/Test-HydrationTemplateNameMatch.ps1
    . $PSScriptRoot/../../Private/Hydration/Resolve-HydrationDeleteDecision.ps1
    . $PSScriptRoot/../../Private/Hydration/Resolve-HydrationMarkedDeleteCandidate.ps1
    . $PSScriptRoot/../../Private/Hydration/Get-HydrationDeleteCandidates.ps1

    function Get-TestTemplateNameSet {
        param(
            [Parameter(Mandatory)]
            [string[]]$Name
        )

        $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($currentName in $Name) {
            [void]$names.Add($currentName)
        }
        return $names
    }
}

Describe 'Get-HydrationDeleteCandidates' {
    BeforeEach {
        $script:ImportPrefix = '[IHD] '
        $script:HydrationMarker = 'Imported by Intune Hydration Kit'
        $script:HydrationMarkerAlt = 'Imported by Intune-Hydration-Kit'
    }

    It 'Should return marked objects that match the current template set' {
        Mock Get-GraphPagedResults {
            @(
                @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
            )
        }
        Mock Invoke-MgGraphRequest {}

        $result = @(Get-HydrationDeleteCandidates `
            -Endpoint 'beta/deviceManagement/deviceConfigurations' `
            -KnownTemplateNames (Get-TestTemplateNameSet -Name 'Test Policy'))

        $result | Should -HaveCount 1
        $result[0].Name | Should -Be '[IHD] Test Policy'
        $result[0].Url | Should -Be '/deviceManagement/deviceConfigurations/policy-1'
        Should -Invoke Invoke-MgGraphRequest -Times 0
    }

    It 'Should fail closed when the template name set is empty' {
        Mock Get-GraphPagedResults {
            @(
                @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
            )
        }
        Mock Invoke-MgGraphRequest {}

        $emptyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $result = @(Get-HydrationDeleteCandidates `
            -Endpoint 'beta/deviceManagement/deviceConfigurations' `
            -KnownTemplateNames $emptyNames)

        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-MgGraphRequest -Times 0
    }

    It 'Should use a targeted GET when the list response omits marker fields' {
        Mock Get-GraphPagedResults {
            @(
                @{ id = 'policy-1'; displayName = '[IHD] Test Policy' }
            )
        }
        Mock Invoke-MgGraphRequest {
            @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit' }
        } -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/deviceConfigurations/policy-1'
        }

        $result = @(Get-HydrationDeleteCandidates `
            -Endpoint 'beta/deviceManagement/deviceConfigurations' `
            -KnownTemplateNames (Get-TestTemplateNameSet -Name 'Test Policy'))

        $result | Should -HaveCount 1
        $result[0].Name | Should -Be '[IHD] Test Policy'
        Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'beta/deviceManagement/deviceConfigurations/policy-1'
        }
    }

    It 'Should skip objects whose full object still lacks the hydration marker' {
        Mock Get-GraphPagedResults {
            @(
                @{ id = 'policy-1'; displayName = '[IHD] Test Policy' }
            )
        }
        Mock Invoke-MgGraphRequest {
            @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Created manually' }
        }

        $result = @(Get-HydrationDeleteCandidates `
            -Endpoint 'beta/deviceManagement/deviceConfigurations' `
            -KnownTemplateNames (Get-TestTemplateNameSet -Name 'Test Policy'))

        $result | Should -BeNullOrEmpty
    }

    It 'Should skip out-of-scope template names without fetching the full object' {
        Mock Get-GraphPagedResults {
            @(
                @{ id = 'policy-1'; displayName = '[IHD] Other Policy'; description = 'Imported by Intune Hydration Kit' }
            )
        }
        Mock Invoke-MgGraphRequest {}

        $result = @(Get-HydrationDeleteCandidates `
            -Endpoint 'beta/deviceManagement/deviceConfigurations' `
            -KnownTemplateNames (Get-TestTemplateNameSet -Name 'Test Policy'))

        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-MgGraphRequest -Times 0
    }

    It 'Should skip objects rejected by the candidate filter' {
        Mock Get-GraphPagedResults {
            @(
                @{ id = 'policy-1'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit'; '@odata.type' = '#microsoft.graph.expectedType' }
                @{ id = 'policy-2'; displayName = '[IHD] Test Policy'; description = 'Imported by Intune Hydration Kit'; '@odata.type' = '#microsoft.graph.otherType' }
            )
        }
        Mock Invoke-MgGraphRequest {}

        $result = @(Get-HydrationDeleteCandidates `
            -Endpoint 'beta/deviceManagement/deviceConfigurations' `
            -KnownTemplateNames (Get-TestTemplateNameSet -Name 'Test Policy') `
            -CandidateFilter { param($candidate) [string]$candidate.'@odata.type' -eq '#microsoft.graph.expectedType' })

        $result | Should -HaveCount 1
        $result[0].Id | Should -Be 'policy-1'
        Should -Invoke Invoke-MgGraphRequest -Times 0
    }
}
