function Invoke-IntuneWinGetAppTemplate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Template,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory
    )

    if ([string]::IsNullOrWhiteSpace($Template.packageIdentifier)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new("WinGet template '$($Template.templateId)' has a missing or blank packageIdentifier."),
            'WinGetTemplateMissingPackageIdentifier',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $Template
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $stagingRoot = Join-Path -Path $WorkingDirectory -ChildPath ('{0}-{1}' -f $Template.templateId, [guid]::NewGuid().ToString('N'))
    $contentRoot = Join-Path -Path $stagingRoot -ChildPath 'content'
    $uploadRoot = Join-Path -Path $stagingRoot -ChildPath 'upload'
    $createdAppId = $null
    $currentStep = 'Resolve package metadata'
    Write-Debug "Processing WinGet template '$($Template.templateId)' for package '$($Template.packageIdentifier)'. TemplatePath='$($Template.TemplatePath)', DisplayName='$DisplayName', StagingRoot='$stagingRoot', ContentRoot='$contentRoot', UploadRoot='$uploadRoot'."

    try {
        $packageMetadata = New-WinGetPackageMetadataFromTemplate -Template $Template
        Write-Debug "Resolved WinGet package metadata for template '$($Template.templateId)': PackageIdentifier='$($packageMetadata.PackageIdentifier)', PackageVersion='$($packageMetadata.PackageVersion)', ManifestPath='$($packageMetadata.ManifestPath)', SelectedInstaller=$(Format-WinGetInstallerSummary -Installer $packageMetadata.SelectedInstaller)."

        $currentStep = 'Create wrapper files'
        $wrapperFiles = New-WinGetWrapperFiles -Path $contentRoot -Template $Template
        Write-Debug "Created WinGet wrapper files for template '$($Template.templateId)': InstallScriptPath='$($wrapperFiles.InstallScriptPath)', UninstallScriptPath='$($wrapperFiles.UninstallScriptPath)'."

        $packagePath = Join-Path -Path $stagingRoot -ChildPath ('{0}.intunewin' -f $Template.templateId)
        $currentStep = 'Create packaging context'
        $installCommandLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Install-WinGetPackage.ps1'
        $uninstallCommandLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Uninstall-WinGetPackage.ps1'
        $packageContext = New-IntuneWinPackagingContext -PackageMetadata $packageMetadata -SourcePath $contentRoot -SetupFile ([System.IO.Path]::GetFileName($wrapperFiles.InstallScriptPath)) -OutputPath $packagePath -InstallCommandLine $installCommandLine -UninstallCommandLine $uninstallCommandLine
        Write-Debug "Created WinGet packaging context for template '$($Template.templateId)' with OutputPath='$packagePath'."

        $currentStep = 'Create .intunewin package'
        $packagedContent = New-IntuneWinPackage -PackagingContext $packageContext
        Write-Debug "Created .intunewin package for template '$($Template.templateId)' at '$($packagedContent.OutputPath)' (SetupFile='$($packagedContent.SetupFile)', UnencryptedSize=$($packagedContent.UnencryptedSize))."

        $iconAsset = $null
        $currentStep = 'Resolve app icon'
        try {
            $iconAsset = Resolve-WinGetAppIcon -Template $Template
            if ($iconAsset) {
                Write-Debug "Resolved icon for '$DisplayName' from '$($iconAsset.Source)' with MimeType='$($iconAsset.MimeType)'."
            }
        } catch {
            Write-Debug "Icon resolution failed for '$DisplayName'. Proceeding without icon. Error='$($_.Exception.Message)'."
            Write-HydrationLog -Message "  Warning: Icon resolution failed for $DisplayName - $($_.Exception.Message)" -Level Warning
        }

        $configuration = @{
            PackageInformation    = @{
                SetupFile = 'Install-WinGetPackage.ps1'
            }
            Information           = @{
                DisplayName     = $DisplayName
                Description     = New-HydrationDescription -ExistingText ([string]$Template.description)
                Publisher       = if ($packageMetadata.Publisher) { $packageMetadata.Publisher } else { [string]$Template.publisher }
                Developer       = [string]$Template.publisher
                Owner           = [string]$Template.metadata.placeholders.owner
                Notes           = New-WinGetOwnershipNotes -Template $Template -PackageMetadata $packageMetadata
                AppVersion      = [string]$packageMetadata.PackageVersion
                RoleScopeTagIds = @($Template.metadata.placeholders.scopeTagIds)
            }
            Program               = @{
                InstallCommand          = $installCommandLine
                UninstallCommand        = $uninstallCommandLine
                InstallExperience       = [string]$Template.install.experience
                DeviceRestartBehavior   = [string]$Template.install.restartBehavior
                AllowAvailableUninstall = ($Template.uninstall.behavior -eq 'allow')
            }
            RequirementRule       = @{
                MinimumSupportedWindowsRelease = [string]$Template.requirements.minimumSupportedWindowsRelease
                Architecture                   = Get-RequirementArchitecture -Architecture $Template.requirements.architectures
                MinimumFreeDiskSpaceInMB       = $Template.requirements.minimumFreeDiskSpaceInMB
                MinimumMemoryInMB              = $Template.requirements.minimumMemoryInMB
            }
            DetectionRule         = @(Get-WinGetDetectionRules -Template $Template -PackageMetadata $packageMetadata)
            CustomRequirementRule = @()
        }

        $currentStep = 'Create Win32 app payload'
        $payload = New-IntuneWin32AppPayload -Configuration $configuration -PackageFileName ([System.IO.Path]::GetFileName($packagePath)) -SetupFilePath 'Install-WinGetPackage.ps1' -ScriptRootPath $contentRoot -IconBase64 $iconAsset.Base64 -IconMimeType $iconAsset.MimeType
        Write-Debug "Created Win32 app payload for '$DisplayName' with AppVersion='$($payload.appVersion)', Rules=$(@($payload.rules).Count), ScopeTags=$(@($payload.roleScopeTagIds).Count)."

        $currentStep = 'Create Graph mobile app'
        $createdApp = Invoke-HydrationGraphRequest -Method POST -Uri 'beta/deviceAppManagement/mobileApps' -Body $payload
        $createdAppId = $createdApp.id
        Write-Debug "Created WinGet Win32 app '$DisplayName' in Graph with AppId='$createdAppId'."

        $currentStep = 'Publish Win32 app content'
        $publishResult = Publish-IntuneWin32AppContent -AppId $createdAppId -IntuneWinPath $packagePath -WorkingDirectory $uploadRoot
        Write-Debug "Published Win32 app content for '$DisplayName'. ContentVersionId='$($publishResult.ContentVersionId)', ContentFileId='$($publishResult.ContentFileId)', UploadedChunkCount=$($publishResult.UploadedChunkCount), PackagePath='$($publishResult.PackagePath)'."
        Write-HydrationLog -Message "  Created: $DisplayName" -Level Info
        return New-HydrationResult -Name $DisplayName -Id $createdAppId -Path $Template.TemplatePath -Type 'WinGetWin32App' -Action 'Created' -Status ([string]$packageMetadata.PackageVersion)
    } catch {
        Write-Debug "WinGet import failed for '$DisplayName' during step '$currentStep'. Error='$($_.Exception.Message)'."
        $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
        if ($createdAppId) {
            try {
                Invoke-HydrationGraphRequest -Method DELETE -Uri "beta/deviceAppManagement/mobileApps/$createdAppId" | Out-Null
                Write-Debug "Deleted partially created WinGet Win32 app '$DisplayName' with AppId='$createdAppId' during cleanup."
                Write-HydrationLog -Message "  CleanupDeleted: $DisplayName" -Level Warning
            } catch {
                Write-Debug "Failed to delete partially created WinGet Win32 app '$DisplayName' with AppId='$createdAppId' during cleanup. Error='$($_.Exception.Message)'."
                Write-HydrationLog -Message "  CleanupFailed: $DisplayName - $($_.Exception.Message)" -Level Warning
            }
        }

        Write-HydrationLog -Message "  Failed: $DisplayName - $errorMessage" -Level Warning
        return New-HydrationResult -Name $DisplayName -Path $Template.TemplatePath -Type 'WinGetWin32App' -Action 'Failed' -Status $errorMessage
    } finally {
        if (Test-Path -Path $stagingRoot) {
            Write-Debug "Removing WinGet staging directory '$stagingRoot' for template '$($Template.templateId)'."
            try {
                Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Debug "Failed to remove WinGet staging directory '$stagingRoot'. Error='$($_.Exception.Message)'."
            }
        }
    }
}
