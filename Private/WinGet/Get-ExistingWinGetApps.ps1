function Get-ExistingWinGetApps {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]]$KnownTemplateNames
    )

    $apps = [System.Collections.Generic.List[object]]::new()
    $appLookup = @{}
    $listUri = "beta/deviceAppManagement/mobileApps?`$select=id,displayName,description,notes"
    $visitedUris = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $pageCount = 0
    $maxPages = 1000

    do {
        $pageCount++
        if ($pageCount -gt $maxPages) {
            throw "Graph pagination exceeded the maximum page limit of $maxPages while listing mobile apps."
        }
        if (-not $visitedUris.Add($listUri)) {
            throw 'Graph pagination returned a repeated nextLink while listing mobile apps.'
        }

        $response = Invoke-HydrationGraphRequest -Method GET -Uri $listUri
        foreach ($existingApp in @($response.value)) {
            $appToEvaluate = $existingApp
            $appName = [string]$existingApp.displayName
            $isPotentialMatch = $KnownTemplateNames.Contains($appName)

            if ($isPotentialMatch -and [string]::IsNullOrWhiteSpace($existingApp.description) -and [string]::IsNullOrWhiteSpace($existingApp.notes)) {
                try {
                    $appToEvaluate = Invoke-HydrationGraphRequest -Method GET -Uri "beta/deviceAppManagement/mobileApps/$($existingApp.id)"
                } catch {
                    Write-Verbose "Could not retrieve full details for app '$appName': $($_.Exception.Message)"
                }
            }

            $isOwned = Test-IntuneWinGetAppOwnership -Description $appToEvaluate.description -Notes $appToEvaluate.notes -ObjectName $appName
            $appRecord = [PSCustomObject]@{
                Id          = $appToEvaluate.id
                DisplayName = $appName
                Description = [string]$appToEvaluate.description
                Notes       = [string]$appToEvaluate.notes
                IsOwned     = $isOwned
            }

            $apps.Add($appRecord)

            if (-not [string]::IsNullOrWhiteSpace($appRecord.DisplayName)) {
                if (-not $appLookup.ContainsKey($appRecord.DisplayName)) {
                    $appLookup[$appRecord.DisplayName] = $appRecord
                } elseif ($appRecord.IsOwned -and -not $appLookup[$appRecord.DisplayName].IsOwned) {
                    $appLookup[$appRecord.DisplayName] = $appRecord
                }
            }
        }

        $listUri = $response.'@odata.nextLink'
    } while ($listUri)

    return [PSCustomObject]@{
        Items  = @($apps)
        Lookup = $appLookup
    }
}
