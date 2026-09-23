# 10. APIM AI Gateway Deep Dive

Azure API Management (APIM) is the controlled gateway between the application
and two backend categories:

1. **A2A agent APIs:** BFF requests enter APIM and are routed to private agent
   endpoints on AKS.
2. **AI model and speech APIs:** Agent requests enter APIM and are forwarded to
   Microsoft Foundry using APIM's managed identity.

APIM is therefore both the **agent API gateway** and the **AI model gateway**.
It provides one governed place for routing, credentials, limits, diagnostics,
and API lifecycle. It does not decide which agent runs next and does not
generate content.

See [Architecture and components](02-architecture.md) for the complete
prompt-to-answer sequence.

## Runtime surfaces

### Agent request path

The BFF uses the Foundry-generated agent facades. Each facade resolves through
the corresponding Bicep-managed origin API before APIM connects to the private
AKS load balancer:

```text
BFF
  -> Foundry-generated agent facade, for example /research-agent
  -> Bicep-managed origin API, for example /agents/research
  -> private AKS LoadBalancer IP
  -> research agent
```

This two-layer design separates the Foundry-facing agent asset from the stable
private backend definition.

### Model and speech path

All three agents use the APIM `/openai` surface rather than connecting directly
to Foundry:

```text
AKS agent
  -> APIM /openai using its APIM subscription value
  -> APIM applies token policy and metrics
  -> APIM obtains a managed-identity token
  -> Microsoft Foundry model or speech deployment
```

## API inventory

| API surface | Path | Provisioning owner | Purpose |
|---|---|---|---|
| Research agent facade | `/research-agent` | Foundry registration | Governed `isAgent=true` A2A facade used by the BFF |
| Creator agent facade | `/creator-agent` | Foundry registration | Governed `isAgent=true` A2A facade used by the BFF |
| Podcaster agent facade | `/podcaster-agent` | Foundry registration | Governed `isAgent=true` A2A facade used by the BFF |
| Research origin API | `/agents/research` | Bicep | Routes to `10.40.15.240:8001` |
| Creator origin API | `/agents/creator` | Bicep | Routes to `10.40.15.241:8002` |
| Podcaster origin API | `/agents/podcaster` | Bicep | Routes to `10.40.15.242:8003` |
| Model gateway | `/openai` | Bicep | Governed chat-completions and audio-speech access to Foundry |
| Generic wildcard API | `/aca-sandbox-foundry` | Platform-generated | Present in APIM but unused by the DevUI/BFF workflow |

The Foundry-generated APIs are visible through the APIM
`2024-10-01-preview` management API because they use `isAgent=true`. Older
stable management API versions can omit those agent facades from inventory
results even though the runtime routes exist.

## APIM responsibilities

| Responsibility | What APIM does in this deployment | Why it is needed |
|---|---|---|
| Stable agent entry points | Exposes `/research-agent`, `/creator-agent`, and `/podcaster-agent` for the BFF. | Clients use governed URLs rather than private AKS addresses. |
| Foundry agent representation | Publishes A2A metadata and connects each generated facade to its registered agent card and JSON-RPC backend. | Foundry can represent and manage the custom agents while traffic remains governed by APIM. |
| Generated facade CORS | Applies the Foundry-generated CORS policy to the agent facades. The application still uses the same-origin BFF path. | Preserves browser compatibility without bypassing the trusted BFF pattern. |
| Origin API routing | Maintains `/agents/research`, `/agents/creator`, and `/agents/podcaster`. | Keeps private backend definitions stable and infrastructure-managed. |
| Private AKS connectivity | Uses outbound VNet integration to reach the three private AKS load balancer addresses. | Agents require no public IP or public ingress. |
| A2A operations | Publishes agent cards, health, task submission, research status, and podcast task polling. Root POST requests are rewritten to `/a2a` on origin APIs. | Supports discovery, synchronous requests, live status, and asynchronous polling. |
| Long requests | Uses a 600-second backend timeout on the Bicep-managed origin APIs. | Research and generation can run longer than ordinary REST calls. |
| A2A credential forwarding | Preserves the bearer token added by the BFF. The destination agent validates it. | The browser never receives the shared agent credential. |
| Model gateway | Exposes chat completions and audio speech below `/openai/deployments/<deployment>`. | All model and speech calls use one governed endpoint. |
| Model caller authentication | Requires an APIM subscription and accepts its value through the configured `api-key` header. | Only approved workloads can consume model capacity. |
| Passwordless Foundry access | Replaces the backend `Authorization` header with a Microsoft Entra token from APIM's system-assigned managed identity. | Foundry credentials are not stored in agent containers or source code. |
| Token-rate governance | Applies `azure-openai-token-limit` per APIM subscription at 100,000 tokens per minute. | Controls consumption and rejects calls that exceed the subscription allowance. |
| Token metrics | Emits Azure OpenAI token metrics with subscription and API dimensions. | Usage can be attributed to a gateway consumer and API. |
| Request diagnostics | Sends agent and model diagnostics to Application Insights with W3C correlation, metrics, 100 percent sampling, and all errors logged. Client IP logging is disabled. | Gateway activity can be correlated with BFF, agent, sandbox, model, storage, and OTEL telemetry. |
| Foundry project connection | Registers the APIM resource and gateway URL as an `ApiManagement` connection under the Foundry project. | Foundry recognizes the existing APIM instance as the project's AI Gateway. |

## Authentication boundaries

| Boundary | Authentication owner | APIM role |
|---|---|---|
| User to DevUI/BFF | Microsoft Entra ID and OAuth2 Proxy | Not in this authentication exchange |
| BFF to agent | BFF supplies the A2A bearer token; agent validates it | Routes the request and preserves the token |
| Agent to APIM model API | APIM subscription value in the `api-key` header | Validates model-gateway access |
| APIM to Foundry | APIM system-assigned managed identity | Acquires and supplies the Foundry bearer token |

The origin A2A APIs do not require APIM subscriptions. Application-layer A2A
authentication remains enforced by the destination agent.

## Network boundary

APIM Standard v2 has outbound VNet integration through the APIM subnet
`10.40.18.0/24`. The three Kubernetes `LoadBalancer` Services use private VNet
addresses:

| Agent | Private origin |
|---|---|
| Research | `10.40.15.240:8001` |
| Creator | `10.40.15.241:8002` |
| Podcaster | `10.40.15.242:8003` |

`loadBalancerSourceRanges` allows only `10.40.18.0/24`, and Cilium independently
enforces the same APIM-source restriction. APIM is therefore the only permitted
network path to these stable private origins.

See [Network design](03-network-design.md) for the complete subnet and policy
model.

## Observability

APIM diagnostics use the shared Application Insights component and W3C trace
correlation. This allows a gateway request to be correlated with:

- BFF request telemetry
- Agent processing spans
- Model and speech dependencies
- Sandbox Broker and ACA Sandbox activity
- Private Blob Storage persistence

The model policy also emits token metrics by APIM subscription and API.

## What APIM does not do

- APIM does not authenticate the human user. Microsoft Entra ID, OAuth2 Proxy,
  and the BFF own that boundary.
- APIM does not orchestrate the workflow. DevUI starts Research first and then
  starts Creator and Podcaster in parallel.
- APIM does not execute agent logic, A2A tasks, or podcast polling state.
- APIM does not create ACA Sandboxes or enforce sandbox egress.
- APIM does not store podcast audio.
- APIM does not provide semantic caching, model load balancing, automatic
  failover, or an APIM content-safety policy in Phase 1.

## Infrastructure source of truth

The APIM resource, project connection, origin APIs, model API, operations,
policies, diagnostics, subscription, managed identity, and Foundry role
assignment are defined in
[`infra/main.bicep`](../infra/main.bicep).
