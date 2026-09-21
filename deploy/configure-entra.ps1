[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$GatewayHostname,

    [string]$ApplicationDisplayName = 'content-factory-devui',
    [string]$ApplicationId,
    [string]$Namespace = 'content-factory',
    [string]$SecretName = 'content-factory-secrets',
    [switch]$RotateClientSecret
)

$ErrorActionPreference = 'Stop'
$annotationName = 'content-factory.azure.com/entra-client-id'
$redirectUri = "https://$GatewayHostname/oauth2/callback"

$secretJson = kubectl -n $Namespace get secret $SecretName --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $secretJson) {
    throw "Kubernetes Secret '$Namespace/$SecretName' was not found. Create the runtime Secret before configuring Entra."
}

$runtimeSecret = $secretJson | ConvertFrom-Json
$annotatedClientId = $runtimeSecret.metadata.annotations.$annotationName
$hasClientSecret = $null -ne $runtimeSecret.data.'oauth-client-secret'
$hasCookieSecret = $null -ne $runtimeSecret.data.'oauth-cookie-secret'

$tenantId = az account show --query tenantId --output tsv
if ($LASTEXITCODE -ne 0 -or -not $tenantId) {
    throw 'Unable to resolve the tenant ID from the active Azure CLI account.'
}

$deployedClientId = $null
$oauthProxyArgs = kubectl -n $Namespace get deployment bff `
    --output 'jsonpath={.spec.template.spec.containers[?(@.name=="oauth2-proxy")].args}' 2>$null
if ($LASTEXITCODE -eq 0 -and $oauthProxyArgs -match '--client-id=([0-9a-fA-F-]{36})') {
    $deployedClientId = $Matches[1]
}

$resolvedFromExistingDeployment = $false
if (-not $ApplicationId -and $annotatedClientId) {
    $ApplicationId = $annotatedClientId
}
elseif (-not $ApplicationId -and $deployedClientId) {
    $ApplicationId = $deployedClientId
    $resolvedFromExistingDeployment = $true
}

$application = $null
if ($ApplicationId) {
    $applicationJson = az ad app show --id $ApplicationId `
        --query '{appId:appId, displayName:displayName, redirectUris:web.redirectUris}' `
        --output json
    if ($LASTEXITCODE -ne 0 -or -not $applicationJson) {
        throw "Unable to resolve Entra application '$ApplicationId' in tenant '$tenantId'."
    }
    $application = $applicationJson | ConvertFrom-Json
}
else {
    $applicationsJson = az ad app list --display-name $ApplicationDisplayName `
        --query '[].{appId:appId, displayName:displayName, redirectUris:web.redirectUris}' `
        --output json
    if ($LASTEXITCODE -ne 0 -or -not $applicationsJson) {
        throw "Unable to search for Entra application '$ApplicationDisplayName'."
    }

    $applications = @($applicationsJson | ConvertFrom-Json)
    if ($applications.Count -gt 1) {
        throw "More than one Entra application is named '$ApplicationDisplayName'. Pass -ApplicationId to select one."
    }

    if ($applications.Count -eq 1) {
        $application = $applications[0]
    }
    else {
        $applicationJson = az ad app create `
            --display-name $ApplicationDisplayName `
            --sign-in-audience AzureADMyOrg `
            --web-redirect-uris $redirectUri `
            --query '{appId:appId, displayName:displayName, redirectUris:web.redirectUris}' `
            --output json
        if ($LASTEXITCODE -ne 0 -or -not $applicationJson) {
            throw "Unable to create Entra application '$ApplicationDisplayName'."
        }
        $application = $applicationJson | ConvertFrom-Json
    }
}

$ApplicationId = $application.appId
$redirectUris = @($application.redirectUris)
if ($redirectUri -notin $redirectUris) {
    $redirectUris += $redirectUri
    $updateArguments = @(
        'ad', 'app', 'update',
        '--id', $ApplicationId,
        '--web-redirect-uris'
    ) + $redirectUris + @('--output', 'none')
    & az @updateArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to add redirect URI '$redirectUri' to Entra application '$ApplicationId'."
    }
}

$servicePrincipalId = az ad sp list `
    --filter "appId eq '$ApplicationId'" `
    --query '[0].id' `
    --output tsv
if ($LASTEXITCODE -ne 0) {
    throw "Unable to query the service principal for Entra application '$ApplicationId'."
}

if (-not $servicePrincipalId) {
    az ad sp create --id $ApplicationId --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create the service principal for Entra application '$ApplicationId'."
    }
}

$secretMatchesApplication = (
    $annotatedClientId -eq $ApplicationId -or
    ($resolvedFromExistingDeployment -and $deployedClientId -eq $ApplicationId)
)
$createClientSecret = $RotateClientSecret -or -not $hasClientSecret -or -not $secretMatchesApplication
$clientSecret = $null
if ($createClientSecret) {
    $credentialName = "content-factory-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
    $clientSecret = az ad app credential reset `
        --id $ApplicationId `
        --append `
        --display-name $credentialName `
        --years 1 `
        --query password `
        --output tsv
    if ($LASTEXITCODE -ne 0 -or -not $clientSecret) {
        throw "Unable to create a client credential for Entra application '$ApplicationId'."
    }
    $clientSecret = $clientSecret.Trim()
}

$cookieSecret = $null
if (-not $hasCookieSecret) {
    $randomBytes = New-Object byte[] 32
    $randomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomNumberGenerator.GetBytes($randomBytes)
    }
    finally {
        $randomNumberGenerator.Dispose()
    }
    $cookieSecret = [Convert]::ToBase64String($randomBytes)
}

$patch = @{
    metadata = @{
        annotations = @{
            $annotationName = $ApplicationId
        }
    }
}

if ($clientSecret -or $cookieSecret) {
    $patch['data'] = @{}
    if ($clientSecret) {
        $patch.data['oauth-client-secret'] =
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($clientSecret))
    }
    if ($cookieSecret) {
        $patch.data['oauth-cookie-secret'] =
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cookieSecret))
    }
}

$patchFile = Join-Path ([IO.Path]::GetTempPath()) "$([Guid]::NewGuid()).json"
try {
    $patchJson = $patch | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($patchFile, $patchJson, $utf8NoBom)
    kubectl -n $Namespace patch secret $SecretName `
        --type merge `
        --patch-file $patchFile | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to update Kubernetes Secret '$Namespace/$SecretName' with the Entra credentials."
    }
}
finally {
    Remove-Item -Path $patchFile -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    ApplicationId       = $ApplicationId
    ApplicationName     = $application.displayName
    TenantId            = $tenantId
    OidcIssuerUrl        = "https://login.microsoftonline.com/$tenantId/v2.0"
    RedirectUri          = $redirectUri
    ClientSecretRotated = $createClientSecret
}
