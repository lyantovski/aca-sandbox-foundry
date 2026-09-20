# 3. Implementation

## Deployment model

The AKS implementation is additive. The original ACA template remains in `Option2/infra/main.bicep`; the new AKS entry point is `Option2/infra/aks/main.bicep`.

## Infrastructure

The AKS template creates:

- VNet and dedicated AKS, AGC, and private-endpoint subnets.
- Private AKS with Azure CNI Overlay and Cilium.
- System and tainted agent node pools.
- OIDC, workload identity, Key Vault CSI, Azure Policy, and Container Insights.
- ACR with the admin account disabled.
- Key Vault and private podcast container.
- Application Insights, Log Analytics, and an Azure Monitor workspace.
- Foundry resource, project, chat model, and optional TTS model.
- APIM with managed identity.
- Application Gateway for Containers resources.
- ACA Sandbox Group.
- Per-workload managed identities and federated credentials.

## Kubernetes packaging

The Helm chart deploys:

- Namespace and workload service accounts.
- Three agent Deployments and ClusterIP Services.
- DevUI, BFF, and sandbox broker.
- OpenTelemetry Collector.
- Default-deny and explicit allow NetworkPolicies.
- Gateway API resources for DevUI and BFF.

The chart never creates credential values. Provide an existing Secret or Key Vault CSI integration.

## Compatibility strategy

- Existing agent images remain independently deployable.
- Broker use is selected with `ACA_SANDBOX_BROKER_URL`.
- Without that setting, local research keeps its original direct ACA Sandbox path.
- DevUI uses relative `/api/agents/*` paths in hosted mode.
- Local Docker Compose provides the same paths through nginx.
- AKS places oauth2-proxy in the BFF pod; the Service targets oauth2-proxy rather than the BFF container directly.

## Known implementation gates

- APIM A2A import and Foundry custom-agent registration require live Azure validation.
- APIM-to-AGC origin mTLS must be configured and tested before agent routes are considered protected.
- AGC AKS add-on availability and API shape must be verified in the deployment region.
- Preview ACA Sandbox API availability must be confirmed.
- Shared-key compatibility remains until every agent library is migrated to managed identity through APIM.
