function New-HydrationRemediationDescription {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template,

        [Parameter(Mandatory)]
        [string]$Fingerprint
    )

    return @(
        $Template.Description
        (New-HydrationDescription)
        'Imported from Proactive Remediation Pack'
        "RemediationTemplateId: $($Template.TemplateId)"
        "RemediationFingerprint: $Fingerprint"
        'Assignments: none'
    ) -join "`n"
}
