# 4. Deployment

This procedure deploys Azure infrastructure, builds workload images, and
installs the AKS Helm release. Remaining operator-owned actions and verification
of Bicep-managed Foundry connections are isolated in
[Manual configuration and verification](05-manual-configuration.md).

## Deployment target

![Deployment target architecture](diagrams/system-architecture.editable-preview.svg)

The deployment creates the Azure and AKS boundaries shown above. Numbered
connectors distinguish application/A2A, identity, model, sandbox/storage, and
telemetry traffic; the editable sources are linked from
[`diagrams/README.md`](diagrams/README.md).

## Prerequisites

- Azure CLI and Bicep CLI
- Azure Developer CLI if using `azd`
- `kubectl`
- Helm 3.14 or later
- Docker or access to ACR Tasks
- Contributor and User Access Administrator at the deployment scope
- Permission to create an Entra application registration, or ownership of an
  existing application passed to the deployment wrapper
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
- APIM model gateway endpoint (the gateway forwards to Foundry)
- Storage account and private endpoint CIDR
- Sandbox subscription, resource group, group, region, and retention
- AGC resource ID, frontend, hostname, and certificate Secret

The workload deployment wrapper injects the Entra tenant, client ID, issuer,
and final gateway hostname. They do not need to be copied into the private
values file.

Do not commit `values.dev.yaml` if it contains environment-specific or secret
material.

## 8. Create the base runtime Secret

Create the non-Entra runtime values before the workload deployment:

```powershell
kubectl create namespace content-factory --dry-run=client -o yaml |
  kubectl apply -f -

kubectl -n content-factory create secret generic content-factory-secrets `
  --from-literal=a2a-auth-token='<generated-value>' `
  --from-literal=model-api-key='<compatibility-value>' `
  --from-literal=sandbox-broker-token='<generated-value>'
```

Do not add the OAuth client or cookie secrets manually. The automated Entra
step patches `oauth-client-secret` and `oauth-cookie-secret` into this Secret
without printing either value.

Use Key Vault CSI for production.

## 9. Configure Entra and deploy workloads

```powershell
$deploymentName = '<infrastructure-deployment-name>'
$devUiHostname = '<devui-hostname>'

.\deploy\deploy-workloads.ps1 `
  -ResourceGroup $resourceGroup `
  -DeploymentName $deploymentName `
  -ValuesFile .\deploy\helm\content-factory\values.dev.yaml `
  -GatewayHostname $devUiHostname
```

`-GatewayHostname` is recommended for an explicit deployment record. When it is
omitted, the wrapper reuses the current Kubernetes Gateway hostname or reads
`gateway.hostname` from the values file.

The wrapper:

1. Reads the Bicep deployment outputs.
2. Runs
   [`deploy/configure-entra.ps1`](../deploy/configure-entra.ps1), which creates
   or reuses the Entra application, adds the callback URI, ensures its service
   principal exists, and patches the OAuth secrets into Kubernetes.
3. Injects the Entra tenant, client ID, issuer, gateway hostname, workload
   identities, and Azure resource values into Helm.
4. Lints and deploys the chart.

On the current lab, the script first adopts the client ID from the deployed
OAuth2 Proxy or the runtime Secret annotation. For an explicitly selected
existing registration, add:

```powershell
-EntraApplicationId '<application-client-id>'
```

The deployment reuses a valid existing Kubernetes client secret. To rotate the
one-year Entra credential intentionally, rerun with
`-RotateEntraClientSecret`.

## 10. Complete manual configuration

Follow [Manual configuration and verification](05-manual-configuration.md) for:

- Verification of the automated Entra configuration
- Trusted TLS
- Verification of the Bicep-managed Foundry APIM connection
- Verification of the Bicep-managed Application Insights connection
- Three Foundry custom-agent registrations

Then execute [Validation and operations](06-validation-and-operations.md).
