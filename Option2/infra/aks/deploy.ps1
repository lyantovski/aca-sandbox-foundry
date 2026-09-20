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
