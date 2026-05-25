function New-WinGetWrapperFiles {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [psobject]$Template
    )

    if (-not (Test-Path -Path $Path)) {
        $null = New-Item -Path $Path -ItemType Directory -Force
    }

    $installScriptPath = Join-Path -Path $Path -ChildPath 'Install-WinGetPackage.ps1'
    $uninstallScriptPath = Join-Path -Path $Path -ChildPath 'Uninstall-WinGetPackage.ps1'
    $detectionScriptPath = Join-Path -Path $Path -ChildPath 'Detect-WinGetPackage.ps1'

    Set-Content -Path $installScriptPath -Value (Get-WinGetWrapperScriptContent -WingetCommand $Template.install.command -PackageIdentifier $Template.packageIdentifier -Operation Install) -Encoding utf8
    Set-Content -Path $uninstallScriptPath -Value (Get-WinGetWrapperScriptContent -WingetCommand $Template.uninstall.command -PackageIdentifier $Template.packageIdentifier -Operation Uninstall) -Encoding utf8
    Set-Content -Path $detectionScriptPath -Value (Get-WinGetDetectionScriptContent -PackageIdentifier $Template.packageIdentifier -DisplayName $Template.displayName -Publisher $Template.publisher) -Encoding utf8
    $null = Save-HydrationGeneratedScript -RelativePath (Join-Path -Path "WinGetApps/$($Template.templateId)" -ChildPath 'Install-WinGetPackage.ps1') -SourcePath $installScriptPath
    $null = Save-HydrationGeneratedScript -RelativePath (Join-Path -Path "WinGetApps/$($Template.templateId)" -ChildPath 'Uninstall-WinGetPackage.ps1') -SourcePath $uninstallScriptPath
    $null = Save-HydrationGeneratedScript -RelativePath (Join-Path -Path "WinGetApps/$($Template.templateId)/Detection" -ChildPath 'Detect-WinGetPackage.ps1') -SourcePath $detectionScriptPath

    return [PSCustomObject]@{
        InstallScriptPath   = $installScriptPath
        UninstallScriptPath = $uninstallScriptPath
        DetectionScriptPath = $detectionScriptPath
    }
}
