# 4. Installation and Deployment

## Planned environment

| Setting | Value |
|---------|-------|
| Region | `swedencentral` |
| Resource group | `aca-sandbox-content-factory-rg` |
| Resource prefix | `aca-sandbox` |
| AKS cluster | `aca-sandbox-aks` |
| ACR | `acracasandboxcf` |
| Foundry | `aca-sandbox-foundry` |
| APIM | `aca-sandbox-apim` |
| Application Gateway for Containers | `aca-sandbox-agc` |
| ACA Sandbox Group | `aca-sandbox-sandbox-group` |

The full resource inventory and layer-by-layer purpose are maintained in
`.azure/deployment-plan.md`.

APIM is deployed on Standard v2 and configured as the AI Gateway. It uses a
dedicated delegated subnet for outbound access to private agent origins.

## Prerequisites

- Azure CLI with access to the target subscription.
- Bicep CLI through `az bicep`.
- `kubectl`.
- Helm 3.14 or later.
- Docker or ACR Tasks for image builds.
- Contributor and User Access Administrator permissions for the deployment scope.
- An Azure region supporting AKS, Application Gateway for Containers, the selected Foundry models, APIM, and ACA Sandboxes.
- DNS name and TLS certificate for DevUI.

## 1. Register providers and preview features

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

az feature register `
  --namespace Microsoft.ContainerService `
  --name ManagedGatewayAPIPreview
az feature register `
  --namespace Microsoft.ContainerService `
  --name ApplicationLoadBalancerPreview
```

Wait until required registrations show `Registered`.

## 2. Validate and deploy infrastructure

```powershell
az login
az account set --subscription '<subscription-id>'

az bicep build --file .\Option2\infra\aks\main.bicep

.\Option2\infra\aks\deploy.ps1 `
  -EnvironmentName aca-sandbox `
  -ResourceGroup aca-sandbox-content-factory-rg `
  -Location swedencentral `
  -ApimPublisherName 'Platform Team' `
  -ApimPublisherEmail 'platform@example.com'
```

Alternatively, use the active `azure.yaml` for infrastructure provisioning:

```powershell
Set-Location .\Option2
azd env new aca-sandbox
azd env set AZURE_LOCATION swedencentral
azd env set AZURE_RESOURCE_GROUP aca-sandbox-content-factory-rg
azd env set AZURE_PRINCIPAL_ID (az ad signed-in-user show --query id -o tsv)
azd env set APIM_PUBLISHER_NAME 'Platform Team'
azd env set APIM_PUBLISHER_EMAIL 'platform@example.com'
azd provision
```

The AKS `azure.yaml` provisions infrastructure only. Image builds and the Helm release remain explicit steps so their versions and values are reviewable.

Review deployment outputs and retain the workload identity client IDs.

## 3. Connect to AKS

The cluster is private. Run these commands from a network with private API-server connectivity:

```powershell
az aks get-credentials `
  --resource-group aca-sandbox-content-factory-rg `
  --name aca-sandbox-aks `
  --overwrite-existing

kubectl get nodes
```

## 4. Enable the AGC add-ons

Application Gateway for Containers add-on commands and feature flags are preview-sensitive. Use the current Microsoft quickstart and pin the versions tested for this environment:

https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-deploy-application-gateway-for-containers-alb-controller-addon

Confirm both the managed Gateway API and Application Load Balancer add-ons are healthy before installing the application chart.

## 5. Build and push images

```powershell
$acr = 'acracasandboxcf'
$tag = '2026.09.19'

az acr build -r $acr -t "agent-research:$tag" .\Option2\Lab\src\agent-research
az acr build -r $acr -t "agent-creator:$tag" .\Option2\Lab\src\agent-creator
az acr build -r $acr -t "agent-podcaster:$tag" .\Option2\Lab\src\agent-podcaster
az acr build -r $acr -t "dev-ui:$tag" .\Option2\Lab\src\dev-ui
az acr build -r $acr -t "bff:$tag" .\Option2\Lab\src\bff
az acr build -r $acr -t "sandbox-broker:$tag" `
  -f .\Option2\Lab\src\sandbox-broker\Dockerfile `
  .\Option2\Lab
```

## 6. Create deployment values

Copy the example and replace every placeholder:

```powershell
Copy-Item `
  .\Option2\deploy\helm\content-factory\values.example.yaml `
  .\Option2\deploy\helm\content-factory\values.dev.yaml
```

Do not commit `values.dev.yaml` if it contains environment-specific or sensitive data.

## 7. Create runtime secrets

Use Key Vault CSI in production. For a short-lived validation environment, create the referenced Kubernetes Secret without storing its values in a file:

```powershell
kubectl create namespace content-factory --dry-run=client -o yaml | kubectl apply -f -

kubectl -n content-factory create secret generic content-factory-secrets `
  --from-literal=a2a-auth-token='<generated-value>' `
  --from-literal=model-api-key='<temporary-apim-or-model-key>' `
  --from-literal=sandbox-broker-token='<generated-value>' `
  --from-literal=oauth-client-secret='<entra-app-secret>' `
  --from-literal=oauth-cookie-secret='<32-byte-random-value>'
```

## 8. Validate and install the chart

```powershell
helm lint .\Option2\deploy\helm\content-factory `
  -f .\Option2\deploy\helm\content-factory\values.dev.yaml

helm upgrade --install content-factory `
  .\Option2\deploy\helm\content-factory `
  --namespace content-factory `
  --create-namespace `
  -f .\Option2\deploy\helm\content-factory\values.dev.yaml `
  --wait `
  --timeout 15m
```

## 9. Configure APIM and Foundry

1. Configure the Foundry model endpoint as an APIM AI backend.
2. Configure one A2A API for each agent.
3. Configure APIM-to-agent-origin authentication and block bypass.
4. Validate each governed agent card.
5. Register each APIM-governed A2A URL as a custom agent in Foundry.
6. Record the generated agent IDs and proxy URLs.

Follow:

- https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities
- https://learn.microsoft.com/azure/api-management/agent-to-agent-api
- https://learn.microsoft.com/azure/foundry/control-plane/register-custom-agent

## 10. Run acceptance checks

Continue with [Validation and operations](05-validation-and-operations.md). Do not describe the environment as working until all required checks pass.
