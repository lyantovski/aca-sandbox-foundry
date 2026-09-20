# 2. Components

| Component | Runtime | Responsibility | Exposure |
|---|---|---|---|
| DevUI | nginx/static HTML | User interface | Public through AGC |
| BFF | FastAPI plus oauth2-proxy sidecar | Same-origin proxy, server-side credentials, Entra auth boundary | Public only through AGC |
| Research agent | Python/LangGraph | Source discovery, ranking, research brief | Private ClusterIP |
| Creator agent | ASP.NET/MAF | Blog and social generation | Private ClusterIP |
| Podcaster agent | Python/Copilot SDK | Script and audio generation | Private ClusterIP |
| Sandbox broker | FastAPI | Authorized ACA Sandbox operations | Private ClusterIP |
| OTEL Collector | OpenTelemetry Collector | Batch and export application telemetry | Private ClusterIP |
| APIM Standard v2 | Azure managed service | AI/model and A2A governance with outbound VNet integration | Governed AI Gateway |
| AGC | Azure managed data plane plus AKS controller | TLS, WAF, routing, health | Public edge |
| Foundry | Azure AI platform | Models, project, agent registry, evaluations | Azure service |
| ACA Sandbox Group | Azure Container Apps | Isolated research execution | Broker-controlled |

## Agent compatibility

The agents retain their current ports and routes:

| Agent | Port | Required routes |
|---|---:|---|
| Research | 8001 | `/health`, `/status`, `/a2a`, `/.well-known/agent.json`, `/.well-known/agent-card.json` |
| Creator | 8002 | `/health`, `/a2a`, `/.well-known/agent.json`, `/.well-known/agent-card.json` |
| Podcaster | 8003 | `/health`, `/a2a`, `/tasks/{id}`, `/.well-known/agent.json`, `/.well-known/agent-card.json` |

## Identities

Use a dedicated Kubernetes service account and federated managed identity for every component that accesses Azure. The broker receives ACA Sandbox permissions; the podcaster receives Blob permissions; model traffic is ultimately mediated by APIM.

## Secrets

The Helm chart references an existing Kubernetes Secret so no secret is committed. Production installation should sync secret material from Key Vault through the CSI driver. Shared A2A/model keys are transitional compatibility inputs and should be removed after all clients use Entra-based APIM authentication.

## API Management Standard v2

AI Gateway is a set of API Management capabilities rather than a separate
pricing tier. Standard v2 is selected for its SLA and outbound VNet integration
to private origins. It is deployed into a dedicated `/24` subnet delegated to
`Microsoft.Web/serverFarms`.

The BFF pod includes oauth2-proxy when `entra.enabled=true`. Application Gateway sends `/api` and `/oauth2` traffic to oauth2-proxy, which completes the OIDC flow and sets trusted identity headers for the loopback-only BFF upstream. The BFF rejects requests without those headers when authentication is enabled.
