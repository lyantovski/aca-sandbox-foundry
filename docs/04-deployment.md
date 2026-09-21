# 4. Deployment

This procedure deploys Azure infrastructure, builds workload images, and
installs the AKS Helm release. Portal-only operations are isolated in
[Manual configuration](05-manual-configuration.md).

## Prerequisites

- Azure CLI and Bicep CLI
- Azure Developer CLI if using `azd`
- `kubectl`
- Helm 3.14 or later
- Docker or access to ACR Tasks
- Contributor and User Access Administrator at the deployment scope
- An Azure region supporting AKS, APIM Standard v2, AGC, Foundry models, and
  ACA Sandboxes

Review [Network design](03-network-design.md) and confirm that `10.40.0.0/16`
does not overlap connected networks.

## 1. Select the Azure context

```powershell
$subscriptionId = '<subscription-id>'
$location = 'swedencentral'
$resourceGroup = '<resource-group>'
$environmentName = '<environment-name>'

az login
az account set --subscription $subscriptionId
```

## 2. Register providers and features

Register these resource providers:

```powershell
$providers = @(
  'Microsoft.ContainerService',
  'Microsoft.Network',
  'Microsoft.NetworkFunction',
  'Microsoft.ServiceNetworking',
  'Microsoft.ManagedIdentity',
  'Microsoft.CognitiveServices',
  'Microsoft.ApiManagement',
  'Microsoft.App',
  'Microsoft.Insights',
  'Microsoft.Monitor',
  'Microsoft.OperationalInsights'
)

foreach ($provider in $providers) {
  az provider register --namespace $provider
}
```

Register any AGC preview features required by the current AKS and AGC
quickstarts, then wait until every required provider and feature is registered.

## 3. Validate infrastructure

```powershell
az bicep build --file .\infra\main.bicep
```

Review the deployment with `what-if` before applying it:

```powershell
az group create --name $resourceGroup --location $location

az deployment group what-if `
  --resource-group $resourceGroup `
  --template-file .\infra\main.bicep `
  --parameters `
    environmentName=$environmentName `
    location=$location `
    apimPublisherName='<publisher-name>' `
    apimPublisherEmail='<publisher-email>'
```

## 4. Deploy infrastructure

Use the checked-in deployment wrapper:

```powershell
.\infra\deploy.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName $environmentName `
  -ResourceGroup $resourceGroup `
  -Location $location `
  -ApimPublisherName '<publisher-name>' `
  -ApimPublisherEmail '<publisher-email>'
```

Alternatively configure an `azd` environment and run `azd provision`.
[`azure.yaml`](../azure.yaml) points directly to [`infra/`](../infra/).

If equivalent role assignments or an Application Insights project connection
already exist, pass their existing resource names through the corresponding
Bicep parameters rather than creating duplicates.

## 5. Connect to AKS

```powershell
$aksName = az deployment group show `
  --resource-group $resourceGroup `
  --name '<deployment-name>' `
  --query properties.outputs.aksName.value -o tsv

az aks get-credentials `
  --resource-group $resourceGroup `
  --name $aksName `
  --overwrite-existing

kubectl get nodes
```

The lab cluster uses a public API endpoint with Entra authentication, Azure
RBAC, and disabled local accounts. Use a private control plane in production.

## 6. Build workload images

Choose immutable image tags:

```powershell
$acr = '<acr-name>'
$tag = '<image-tag>'

az acr build -r $acr -t "agent-research:$tag" .\src\agent-research
az acr build -r $acr -t "agent-creator:$tag" .\src\agent-creator
az acr build -r $acr -t "agent-podcaster:$tag" .\src\agent-podcaster
az acr build -r $acr -t "dev-ui:$tag" .\src\dev-ui
az acr build -r $acr -t "bff:$tag" .\src\bff
az acr build -r $acr -t "sandbox-broker:$tag" `
  -f .\src\sandbox-broker\Dockerfile .
```

The broker build context must be the repository root because its image includes
the shared sandbox execution tool.

## 7. Prepare Helm values

```powershell
Copy-Item `
  .\deploy\helm\content-factory\values.example.yaml `
  .\deploy\helm\content-factory\values.dev.yaml
```

Set:

- ACR login server and immutable image tags
- Workload identity client IDs
- APIM-governed agent URLs
- Foundry endpoint
- Storage account and private endpoint CIDR
- Sandbox subscription, resource group, group, region, and retention
- Entra tenant, client ID, and issuer
- AGC resource ID, frontend, hostname, and certificate Secret

Do not commit `values.dev.yaml` if it contains environment-specific or secret
material.

## 8. Create runtime secrets

For the lab:

```powershell
kubectl create namespace content-factory --dry-run=client -o yaml |
  kubectl apply -f -

kubectl -n content-factory create secret generic content-factory-secrets `
  --from-literal=a2a-auth-token='<generated-value>' `
  --from-literal=model-api-key='<compatibility-value>' `
  --from-literal=sandbox-broker-token='<generated-value>' `
  --from-literal=oauth-client-secret='<entra-client-secret>' `
  --from-literal=oauth-cookie-secret='<32-byte-random-value>'
```

Use Key Vault CSI for production.

## 9. Validate and deploy workloads

```powershell
helm lint .\deploy\helm\content-factory `
  -f .\deploy\helm\content-factory\values.dev.yaml

helm template content-factory .\deploy\helm\content-factory `
  -f .\deploy\helm\content-factory\values.dev.yaml > $null

helm upgrade --install content-factory `
  .\deploy\helm\content-factory `
  --namespace content-factory `
  --create-namespace `
  -f .\deploy\helm\content-factory\values.dev.yaml `
  --wait `
  --timeout 15m
```

The helper [`deploy/deploy-workloads.ps1`](../deploy/deploy-workloads.ps1) can
read Bicep deployment outputs and apply the corresponding workload identity and
resource values.

## 10. Complete manual configuration

Follow [Manual configuration](05-manual-configuration.md) for:

- Entra callback and secrets
- Trusted TLS
- Foundry AI Gateway association
- Application Insights project connection
- Three Foundry custom-agent registrations

Then execute [Validation and operations](06-validation-and-operations.md).
