[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9-]{3,20}$')]
    [string]$EnvironmentName,

    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$Location,

    [Parameter(Mandatory)]
    [string]$ApimPublisherName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$ApimPublisherEmail,

    [string]$AksAdminPrincipalId,

    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'
$template = Join-Path $PSScriptRoot 'main.bicep'

if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) { throw 'Unable to select the Azure subscription.' }
}

if (-not $AksAdminPrincipalId) {
    $AksAdminPrincipalId = az ad signed-in-user show --query id --output tsv
    if ($LASTEXITCODE -ne 0 -or -not $AksAdminPrincipalId) {
        throw 'Unable to resolve the signed-in user object ID. Pass -AksAdminPrincipalId explicitly.'
    }
}

az bicep build --file $template --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep validation failed.' }

az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { throw 'Resource group creation failed.' }

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $template `
    --parameters `
        environmentName=$EnvironmentName `
        location=$Location `
        apimPublisherName=$ApimPublisherName `
        apimPublisherEmail=$ApimPublisherEmail `
        aksAdminPrincipalId=$AksAdminPrincipalId

if ($LASTEXITCODE -ne 0) { throw 'ACA Sandbox Content Factory infrastructure deployment failed.' }

$acrName = "acr$($EnvironmentName.Replace('-', ''))cf"
az aks update `
    --name "$EnvironmentName-aks" `
    --resource-group $ResourceGroup `
    --attach-acr $acrName `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Unable to attach ACR to the AKS kubelet identity.' }

az aks update `
    --name "$EnvironmentName-aks" `
    --resource-group $ResourceGroup `
    --enable-gateway-api `
    --enable-application-load-balancer `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Unable to enable the Gateway API and ALB Controller add-ons.' }

$albPrincipalId = az aks show `
    --name "$EnvironmentName-aks" `
    --resource-group $ResourceGroup `
    --query ingressProfile.applicationLoadBalancer.identity.objectId `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $albPrincipalId) {
    throw 'Unable to resolve the ALB Controller managed identity.'
}

$resourceGroupId = az group show --name $ResourceGroup --query id --output tsv
$agcSubnetId = az network vnet subnet show `
    --resource-group $ResourceGroup `
    --vnet-name "$EnvironmentName-vnet" `
    --name agc `
    --query id `
    --output tsv

az role assignment create `
    --assignee-object-id $albPrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role 'AppGw for Containers Configuration Manager' `
    --scope $resourceGroupId `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Unable to grant ALB Controller configuration access.' }

az role assignment create `
    --assignee-object-id $albPrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role 'Network Contributor' `
    --scope $agcSubnetId `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Unable to grant ALB Controller subnet access.' }
