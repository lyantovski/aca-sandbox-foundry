[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$DeploymentName,

    [Parameter(Mandatory)]
    [string]$ValuesFile,

    [string]$GatewayHostname,

    [string]$ReleaseName = 'content-factory',
    [string]$Namespace = 'content-factory',
    [string]$SecretName = 'content-factory-secrets',
    [string]$EntraApplicationId,
    [string]$EntraApplicationDisplayName,
    [switch]$RotateEntraClientSecret
)

$ErrorActionPreference = 'Stop'
$chart = Join-Path $PSScriptRoot 'helm\content-factory'

if (-not (Test-Path $ValuesFile -PathType Leaf)) {
    throw "Values file not found: $ValuesFile"
}

if (-not $GatewayHostname) {
    $GatewayHostname = kubectl -n $Namespace get gateway content-factory `
        --output 'jsonpath={.spec.listeners[0].hostname}' 2>$null
}

if (-not $GatewayHostname) {
    $valuesContent = Get-Content -Path $ValuesFile -Raw
    $gatewayBlock = [regex]::Match(
        $valuesContent,
        '(?ms)^gateway:\s*\r?\n(?<content>(?:^[ \t]+.*(?:\r?\n|$))*)'
    )
    if ($gatewayBlock.Success) {
        $hostnameMatch = [regex]::Match(
            $gatewayBlock.Groups['content'].Value,
            '(?m)^[ \t]+hostname:\s*["'']?(?<hostname>[^"''#\s]+)'
        )
        if ($hostnameMatch.Success) {
            $GatewayHostname = $hostnameMatch.Groups['hostname'].Value
        }
    }
}

if (-not $GatewayHostname) {
    throw 'Gateway hostname was not found. Pass -GatewayHostname or set gateway.hostname in the values file.'
}

$outputs = az deployment group show `
    --resource-group $ResourceGroup `
    --name $DeploymentName `
    --query properties.outputs `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0 -or -not $outputs) {
    throw 'Unable to read infrastructure deployment outputs.'
}

$identities = $outputs.workloadIdentityClientIds.value

$entraArguments = @{
    GatewayHostname    = $GatewayHostname
    Namespace          = $Namespace
    SecretName         = $SecretName
    RotateClientSecret = $RotateEntraClientSecret
}
if ($EntraApplicationId) {
    $entraArguments.ApplicationId = $EntraApplicationId
}
if ($EntraApplicationDisplayName) {
    $entraArguments.ApplicationDisplayName = $EntraApplicationDisplayName
}
else {
    $entraArguments.ApplicationDisplayName = "$ReleaseName-devui-$ResourceGroup"
}

$entra = & (Join-Path $PSScriptRoot 'configure-entra.ps1') @entraArguments
if (-not $entra -or -not $entra.ApplicationId) {
    throw 'Entra application configuration did not return a client ID.'
}
Write-Host "Configured Entra application '$($entra.ApplicationName)' ($($entra.ApplicationId))."

helm lint $chart -f $ValuesFile
if ($LASTEXITCODE -ne 0) { throw 'Helm lint failed.' }

helm upgrade --install $ReleaseName $chart `
    --namespace $Namespace `
    --create-namespace `
    --values $ValuesFile `
    --set-string "global.imageRegistry=$($outputs.acrLoginServer.value)" `
    --set-string "global.workloadIdentityClientIds.research=$($identities.research)" `
    --set-string "global.workloadIdentityClientIds.creator=$($identities.creator)" `
    --set-string "global.workloadIdentityClientIds.podcaster=$($identities.podcaster)" `
    --set-string "global.workloadIdentityClientIds.bff=$($identities.bff)" `
    --set-string "global.workloadIdentityClientIds.sandboxBroker=$($identities.sandboxBroker)" `
    --set-string "config.foundryEndpoint=$($outputs.apimGatewayUrl.value)" `
    --set-string "config.storageAccountName=$($outputs.storageAccountName.value)" `
    --set-string "config.sandboxResourceGroup=$ResourceGroup" `
    --set-string "config.sandboxGroupName=$($outputs.sandboxGroupResourceId.value.Split('/')[-1])" `
    --set-string "config.applicationInsightsConnectionString=$($outputs.applicationInsightsConnectionString.value)" `
    --set-string "entra.tenantId=$($entra.TenantId)" `
    --set-string "entra.clientId=$($entra.ApplicationId)" `
    --set-string "entra.oidcIssuerUrl=$($entra.OidcIssuerUrl)" `
    --set-string "gateway.hostname=$GatewayHostname" `
    --set-string "gateway.applicationGatewayId=$($outputs.applicationGatewayForContainersId.value)" `
    --set-string "gateway.frontendName=$($outputs.applicationGatewayFrontendId.value.Split('/')[-1])" `
    --wait `
    --timeout 15m

if ($LASTEXITCODE -ne 0) { throw 'Helm deployment failed.' }
