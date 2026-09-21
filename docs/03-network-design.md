# 3. Network Design and Security Flow

## Network topology

![Network design](diagrams/network-design.editable-preview.svg)

The preview uses the exact coordinates, color legend, numbered flows, and
orthogonal connector routing of the editable
[`network-design.excalidraw`](diagrams/network-design.excalidraw) and
[`network-design.drawio`](diagrams/network-design.drawio) sources. The compact
Mermaid source is [`network-design.mmd`](diagrams/network-design.mmd).

## Address plan

| Network | CIDR or address | Purpose |
|---|---|---|
| Lab VNet | `10.40.0.0/16` | Shared network boundary |
| AKS subnet | `10.40.0.0/20` | Nodes, pods, and internal load balancers |
| AGC subnet | `10.40.16.0/24` | AGC association and data plane |
| Private endpoint subnet | `10.40.17.0/24` | Storage private endpoint |
| APIM subnet | `10.40.18.0/24` | APIM Standard v2 outbound integration |
| Research origin | `10.40.15.240:8001` | APIM-only internal load balancer |
| Creator origin | `10.40.15.241:8002` | APIM-only internal load balancer |
| Podcaster origin | `10.40.15.242:8003` | APIM-only internal load balancer |
| Blob private endpoint | `10.40.17.4:443` | Podcaster persistence |

These are the default lab addresses from [`infra/main.bicep`](../infra/main.bicep).
Change them together in Bicep and Helm values if the target network overlaps.

## Inbound flow

1. Internet clients reach only AGC on HTTPS.
2. AGC routes `/` to DevUI NGINX, which returns the static application to the
   browser.
3. DevUI JavaScript in the browser calls same-origin `/api/agents/*` and
   `/api/me` routes through AGC.
4. AGC routes `/api` and `/oauth2` to the BFF Service, whose target is
   oauth2-proxy when Entra authentication is enabled.
5. Without a valid session, oauth2-proxy returns an OIDC redirect to the
   browser.
6. The browser authenticates with Microsoft Entra ID and returns through
   `/oauth2/callback` on AGC.
7. OAuth2 Proxy creates the secure session cookie and forwards authenticated
   requests to the loopback BFF container with trusted identity headers.
8. No agent Service is internet-facing.

The current lab listener uses a self-signed certificate. Production requires a
custom DNS name and trusted Kubernetes TLS secret or a trusted frontend service.

## Governed A2A flow

1. BFF calls APIM over HTTPS.
2. APIM uses outbound VNet integration from `10.40.18.0/24`.
3. Each agent has a fixed internal load balancer address.
4. `externalTrafficPolicy: Local` preserves the APIM source.
5. Cilium NetworkPolicy allows the agent port only from the APIM subnet.
6. A shared A2A bearer token remains a compatibility control until Entra-based
   origin authentication is implemented end to end.

The BFF reaches APIM deliberately. It prevents the browser from receiving A2A
credentials, ensures all agent calls use stable governed endpoints, and applies
APIM authentication, throttling, routing, and diagnostics before traffic
reaches private AKS origins.

## Foundry and model flow

All three agents send Azure OpenAI-compatible requests to the APIM gateway.
APIM's `/openai` API authenticates to the Foundry model resource with managed
identity and forwards the request. This path is independent of Foundry custom
agent registration.

Foundry custom-agent assets store the three APIM-governed A2A URLs. A Foundry
caller invokes an asset through APIM just like the BFF does. Foundry does not
connect directly to the private AKS Services.

### APIM API inventory

The agent APIs appear in pairs because the two entries serve different roles:

| APIM API | Path | Owner and purpose |
|---|---|---|
| `Research A2A Agent` | `/agents/research` | Bicep-managed origin API that routes to the private research load balancer |
| `research-agent` | `/research-agent` | Foundry-generated `isAgent=true` API that uses the research agent card |
| `Creator A2A Agent` | `/agents/creator` | Bicep-managed origin API that routes to the private creator load balancer |
| `creator-agent` | `/creator-agent` | Foundry-generated `isAgent=true` API that uses the creator agent card |
| `Podcaster A2A Agent` | `/agents/podcaster` | Bicep-managed origin API that routes to the private podcaster load balancer |
| `podcaster-agent` | `/podcaster-agent` | Foundry-generated `isAgent=true` API that uses the podcaster agent card |
| `Foundry Model Gateway` | `/openai` | Bicep-managed model and TTS API used by all three agents |

The BFF currently calls the lowercase Foundry-generated paths. Each generated
agent API references the corresponding `/agents/*` agent-card URL, so both
layers are required by the current Foundry registration design.

Foundry AI Gateway association also created a generic
`aca-sandbox-foundry` wildcard API. No deployed workload currently references
its path, and the live API has no backend or API policy. Treat it as a
platform-managed cleanup candidate, not as an active runtime dependency.
Remove it only after verifying that Foundry gateway association, model
playground access, agent registration, and an end-to-end workflow still pass;
Foundry may recreate it.

## Sandbox flow

The research agent cannot access ACA Sandbox control APIs. It calls the broker
on port 8010. The broker uses Workload Identity and the Sandbox Group data owner
role to create and manage individual sandboxes.

Each sandbox receives:

- `default_action=Deny`
- Allow rules for its assigned source domains
- Package endpoints required by the execution image
- Full traffic inspection

An intentional Bing request demonstrates default-deny behavior. Bing is absent
from the configured rule list because it is implicitly denied, not because an
explicit Bing deny rule exists.

## Storage flow

Storage public network access is disabled. The podcaster resolves the Blob
endpoint through private DNS and may connect only to `10.40.17.4/32` on HTTPS.
Its managed identity has Storage Blob Data Contributor.

## Telemetry flow

Application workloads send OTLP/gRPC to the in-cluster collector on port 4317.
The collector exports to Application Insights. APIM also writes request and
dependency telemetry to the same component. Azure platform logs are stored in
Log Analytics.

Telemetry must not capture authorization headers, cookies, model credentials,
prompts, generated customer content, or sandbox tokens by default.

## Network policy model

- Namespace ingress and egress are denied by default.
- DNS is explicitly allowed.
- BFF may reach APIM over HTTPS.
- APIM may reach only the three private agent origins.
- Research may reach the broker.
- Broker may reach ACA Sandbox endpoints over HTTPS.
- Podcaster may reach the Blob private endpoint.
- Instrumented workloads may reach the OTEL Collector.
- Internet egress is granted only where a workload requires it.

Validate the implemented policies in
[`deploy/helm/content-factory/templates/networkpolicies.yaml`](../deploy/helm/content-factory/templates/networkpolicies.yaml).
