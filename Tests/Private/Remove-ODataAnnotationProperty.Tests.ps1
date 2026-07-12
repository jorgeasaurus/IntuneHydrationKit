#Requires -Modules Pester

BeforeAll {
    # Import the function under test
    $functionPath = Join-Path $PSScriptRoot '..\..\Private\Graph\Remove-ODataAnnotationProperty.ps1'
    . $functionPath
}

Describe 'Remove-ODataAnnotationProperty' {
    Context 'When removing annotation properties' {
        It 'Should remove plain @odata annotations' {
            $obj = '{"@odata.context":"https://graph.microsoft.com/x","displayName":"Test"}' | ConvertFrom-Json

            $null = Remove-ODataAnnotationProperty -InputObject $obj

            $obj.PSObject.Properties.Name | Should -Not -Contain '@odata.context'
            $obj.displayName | Should -Be 'Test'
        }

        It 'Should remove prefixed annotations like authenticationStrength@odata.context' {
            $json = '{"grantControls":{"operator":"OR","authenticationStrength@odata.context":"https://graph.microsoft.com/x","authenticationStrength":null}}'
            $obj = $json | ConvertFrom-Json

            $null = Remove-ODataAnnotationProperty -InputObject $obj

            $obj.grantControls.PSObject.Properties.Name | Should -Not -Contain 'authenticationStrength@odata.context'
            $obj.grantControls.operator | Should -Be 'OR'
        }

        It 'Should keep @odata.type properties' {
            $json = '{"conditions":{"users":{"targets":[{"@odata.type":"#microsoft.graph.conditionalAccessAllExternalTenants","membershipKind":"all"}]}}}'
            $obj = $json | ConvertFrom-Json

            $null = Remove-ODataAnnotationProperty -InputObject $obj

            $obj.conditions.users.targets[0].'@odata.type' | Should -Be '#microsoft.graph.conditionalAccessAllExternalTenants'
        }

        It 'Should clean nested objects inside arrays' {
            $json = '{"items":[{"name@odata.context":"x","name":"a"},{"name@odata.context":"y","name":"b"}]}'
            $obj = $json | ConvertFrom-Json

            $null = Remove-ODataAnnotationProperty -InputObject $obj

            foreach ($item in $obj.items) {
                $item.PSObject.Properties.Name | Should -Not -Contain 'name@odata.context'
            }
            $obj.items[1].name | Should -Be 'b'
        }

        It 'Should handle null input without error' {
            { Remove-ODataAnnotationProperty -InputObject $null } | Should -Not -Throw
        }
    }

    Context 'When cleaning real Conditional Access templates' {
        It 'Should strip all annotations except @odata.type from bundled CA templates' {
            $templateDir = Join-Path $PSScriptRoot '..\..\Templates\ConditionalAccess'
            $templates = Get-ChildItem -Path $templateDir -Filter '*.json' -File

            $templates | Should -Not -BeNullOrEmpty

            foreach ($template in $templates) {
                $policy = Get-Content -Path $template.FullName -Raw | ConvertFrom-Json
                $null = Remove-ODataAnnotationProperty -InputObject $policy
                $serialized = $policy | ConvertTo-Json -Depth 20 -Compress
                # No annotations besides @odata.type should survive
                $withoutType = $serialized -replace '"@odata\.type"', ''
                $withoutType | Should -Not -Match '@odata\.'
            }
        }
    }
}
