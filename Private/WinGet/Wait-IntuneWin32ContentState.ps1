function Wait-IntuneWin32ContentState {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ContentVersionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FileId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DesiredState,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$PollIntervalSeconds = 5,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds = 180
    )

    $fileUri = "beta/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions/$ContentVersionId/files/$FileId"
    Write-Debug "Waiting for Win32 content file '$FileId' for app '$AppId' to reach upload state '$DesiredState' (PollIntervalSeconds=$PollIntervalSeconds, TimeoutSeconds=$TimeoutSeconds)."

    $elapsedSeconds = 0
    while ($elapsedSeconds -le $TimeoutSeconds) {
        $file = Invoke-HydrationGraphRequest -Method GET -Uri $fileUri
        Write-Debug "Win32 content file '$FileId' current upload state is '$($file.uploadState)' after $elapsedSeconds second(s)."

        if ($file.uploadState -eq $DesiredState) {
            Write-Debug "Win32 content file '$FileId' reached desired upload state '$DesiredState'."
            return $file
        }

        if ($file.uploadState -eq 'commitFileFailed') {
            throw "Win32 content file commit failed for file '$FileId'."
        }

        $remainingSeconds = $TimeoutSeconds - $elapsedSeconds
        if ($remainingSeconds -le 0) {
            break
        }

        $sleepSeconds = [Math]::Min($PollIntervalSeconds, $remainingSeconds)
        Start-Sleep -Seconds $sleepSeconds
        $elapsedSeconds += $sleepSeconds
    }

    $timeoutMessage = "Timed out waiting for upload state '$DesiredState' for file '$FileId'."
    Write-Debug "Timed out waiting for Win32 content file '$FileId' to reach upload state '$DesiredState'."
    throw $timeoutMessage
}
