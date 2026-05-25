function Resolve-HydrationSettingsSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [hashtable]$Schema,

        [Parameter()]
        [string]$SchemaPath = 'root'
    )

    function New-SettingsValidationError {
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [Parameter(Mandatory)]
            [string]$ErrorId,

            [Parameter(Mandatory)]
            [System.Management.Automation.ErrorCategory]$Category,

            [Parameter()]
            [object]$TargetObject
        )

        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message),
            $ErrorId,
            $Category,
            $TargetObject
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    function Get-SchemaTypes {
        param(
            [Parameter()]
            [object]$TypeValue
        )

        if ($null -eq $TypeValue) {
            return @()
        }

        if ($TypeValue -is [System.Array]) {
            return @($TypeValue)
        }

        return @($TypeValue)
    }

    function Test-ValueMatchesSchema {
        param(
            [Parameter()]
            [object]$Value,

            [Parameter(Mandatory)]
            [hashtable]$ValueSchema,

            [Parameter(Mandatory)]
            [string]$ValuePath
        )

        $schemaTypes = Get-SchemaTypes -TypeValue $ValueSchema.type
        if ($null -eq $Value) {
            if ('null' -in $schemaTypes) {
                return
            }

            New-SettingsValidationError -Message "Property '$ValuePath' cannot be null." -ErrorId 'InvalidSettingsNull' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject $ValuePath
        }

        if ('object' -in $schemaTypes) {
            if ($Value -isnot [System.Collections.IDictionary]) {
                New-SettingsValidationError -Message "Property '$ValuePath' must be an object." -ErrorId 'InvalidSettingsType' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject $ValuePath
            }

            Resolve-SettingsObject -SettingsObject $Value -ObjectSchema $ValueSchema -ObjectPath $ValuePath
            return
        }

        if ('array' -in $schemaTypes) {
            if ($Value -isnot [System.Array]) {
                New-SettingsValidationError -Message "Property '$ValuePath' must be an array." -ErrorId 'InvalidSettingsType' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject $ValuePath
            }

            if ($ValueSchema.items) {
                for ($i = 0; $i -lt $Value.Count; $i++) {
                    Test-ValueMatchesSchema -Value $Value[$i] -ValueSchema $ValueSchema.items -ValuePath "$ValuePath[$i]"
                }
            }
            return
        }

        if ('string' -in $schemaTypes) {
            if ($Value -isnot [string]) {
                New-SettingsValidationError -Message "Property '$ValuePath' must be a string." -ErrorId 'InvalidSettingsType' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject $ValuePath
            }

            if ($ValueSchema.enum -and $Value -notin $ValueSchema.enum) {
                New-SettingsValidationError -Message "Property '$ValuePath' must be one of: $($ValueSchema.enum -join ', ')." -ErrorId 'InvalidSettingsEnum' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject $ValuePath
            }

            if ($ValueSchema.pattern -and $Value -notmatch $ValueSchema.pattern) {
                New-SettingsValidationError -Message "Property '$ValuePath' does not match the required format." -ErrorId 'InvalidSettingsPattern' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject $ValuePath
            }

            return
        }

        if ('boolean' -in $schemaTypes) {
            if ($Value -isnot [bool]) {
                New-SettingsValidationError -Message "Property '$ValuePath' must be a boolean." -ErrorId 'InvalidSettingsType' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject $ValuePath
            }
        }
    }

    function Resolve-SettingsObject {
        param(
            [Parameter(Mandatory)]
            [System.Collections.IDictionary]$SettingsObject,

            [Parameter(Mandatory)]
            [hashtable]$ObjectSchema,

            [Parameter(Mandatory)]
            [string]$ObjectPath
        )

        foreach ($requiredProperty in @($ObjectSchema.required | Where-Object { $null -ne $_ })) {
            if (-not $SettingsObject.Contains($requiredProperty)) {
                New-SettingsValidationError -Message "Missing required field: $ObjectPath.$requiredProperty" -ErrorId 'MissingRequiredSetting' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject "$ObjectPath.$requiredProperty"
            }
        }

        foreach ($propertyName in @($ObjectSchema.properties.Keys | Where-Object { $null -ne $_ })) {
            $propertySchema = $ObjectSchema.properties[$propertyName]
            $propertyPath = "$ObjectPath.$propertyName"
            $hasProperty = $SettingsObject.Contains($propertyName)

            if (-not $hasProperty) {
                if ($propertySchema.ContainsKey('default')) {
                    $SettingsObject[$propertyName] = $propertySchema.default
                    $hasProperty = $true
                } elseif ((Get-SchemaTypes -TypeValue $propertySchema.type) -contains 'object' -and $propertySchema.properties) {
                    $hasNestedDefaults = $false
                    foreach ($nestedPropertyName in @($propertySchema.properties.Keys)) {
                        if ($propertySchema.properties[$nestedPropertyName].ContainsKey('default')) {
                            $hasNestedDefaults = $true
                            break
                        }
                    }

                    if ($hasNestedDefaults) {
                        $SettingsObject[$propertyName] = @{}
                        $hasProperty = $true
                    }
                }
            }

            if ($hasProperty) {
                Test-ValueMatchesSchema -Value $SettingsObject[$propertyName] -ValueSchema $propertySchema -ValuePath $propertyPath
            }
        }
    }

    Resolve-SettingsObject -SettingsObject $Settings -ObjectSchema $Schema -ObjectPath $SchemaPath

    $authMode = $Settings.authentication.mode
    if ($authMode -eq 'clientSecret') {
        if ([string]::IsNullOrWhiteSpace($Settings.authentication.clientId)) {
            New-SettingsValidationError -Message "Missing required field for clientSecret authentication: root.authentication.clientId" -ErrorId 'MissingClientId' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject 'root.authentication.clientId'
        }

        if ([string]::IsNullOrWhiteSpace($Settings.authentication.clientSecret)) {
            New-SettingsValidationError -Message "Missing required field for clientSecret authentication: root.authentication.clientSecret" -ErrorId 'MissingClientSecret' -Category ([System.Management.Automation.ErrorCategory]::InvalidData) -TargetObject 'root.authentication.clientSecret'
        }
    }

    return $Settings
}
