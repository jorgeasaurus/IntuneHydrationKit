function ConvertTo-HydrationOAuthScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Scopes,

        [Parameter(Mandatory)]
        [string]$GraphEndpoint
    )

    $oidcScopes = @('openid', 'profile', 'offline_access', 'email')
    $graphResource = $GraphEndpoint.TrimEnd('/')

    return @(foreach ($scope in $Scopes) {
            if ($scope -like 'https://*' -or $scope -in $oidcScopes) {
                $scope
            } else {
                "$graphResource/$scope"
            }
        })
}
