[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$DeploymentName,

    [Parameter(Mandatory)]
    [string]$ValuesFile,

    [string]$ReleaseName = 'content-factory',
    [string]$Namespace = 'content-factory'
)

$ErrorActionPreference = 'Stop'
$chart = Join-Path $PSScriptRoot 'helm\content-factory'

if (-not (Test-Path $ValuesFile -PathType Leaf)) {
    throw "Values file not found: $ValuesFile"
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
    --set-string "config.foundryEndpoint=$($outputs.foundryEndpoint.value)" `
    --set-string "config.storageAccountName=$($outputs.storageAccountName.value)" `
    --set-string "config.sandboxResourceGroup=$ResourceGroup" `
    --set-string "config.sandboxGroupName=$($outputs.sandboxGroupResourceId.value.Split('/')[-1])" `
    --set-string "config.applicationInsightsConnectionString=$($outputs.applicationInsightsConnectionString.value)" `
    --wait `
    --timeout 15m

if ($LASTEXITCODE -ne 0) { throw 'Helm deployment failed.' }
