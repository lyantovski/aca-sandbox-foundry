# 1. Architecture

## Goals

- Host the existing agents and DevUI on AKS.
- Keep agent behavior and A2A contracts stable.
- Keep ACA Sandboxes as an external isolated execution service.
- Govern A2A and model traffic with APIM AI Gateway.
- Register the governed agents in Microsoft Foundry.
- Expose DevUI with Application Gateway for Containers.
- Capture application telemetry in Application Insights.
- Prepare, but do not install, KARS.

## Layers

### Edge

Application Gateway for Containers terminates TLS, applies WAF policy, and routes `/` to DevUI and `/api` to the BFF. Agent backends remain private.

### Web

DevUI is static content. The BFF is the browser security boundary: it performs server-side downstream authentication, forwards requests, normalizes errors, and prevents reusable credentials from reaching the browser.

### AI gateway

APIM Standard v2 acts as the AI Gateway for model and A2A traffic. AI Gateway
is an APIM capability set, not a separate pricing tier. Standard v2 applies
identity validation, quotas, throttling, diagnostics, and correlation, and its
outbound VNet integration reaches private AKS origins. Foundry custom-agent
registration uses APIM-governed agent URLs.

### Agent runtime

The research, creator, and podcaster services run as independent AKS Deployments with private ClusterIP Services. Their existing health, agent-card, A2A, status, and task APIs are preserved.

### Sandbox execution

The sandbox broker is a new private AKS microservice. It owns ACA Sandbox permissions and exposes a narrow task API to the research agent. This boundary also matches the future KARS rule that an agent should not hold Azure control-plane credentials.

### Observability

Application components emit OTLP telemetry to an in-cluster OpenTelemetry Collector. Application Insights is the distributed tracing destination. Azure Monitor, Log Analytics, and managed Prometheus collect AKS and Azure platform signals.

## Trust boundaries

1. Internet to Application Gateway for Containers.
2. Authenticated browser session to BFF.
3. BFF or Foundry caller to APIM.
4. APIM to the protected AKS agent origin.
5. Research agent to sandbox broker.
6. Workload identities to Azure services.

No direct internet route to an agent Service is permitted.

## KARS-ready meaning

The AKS baseline enables OIDC, workload identity, Azure CNI powered by Cilium, restricted pod security, dedicated agent nodes, Key Vault CSI, and monitoring. Cilium is the current KARS AKS reference path, not a mechanical Helm-install requirement. A different conformant NetworkPolicy implementation requires explicit KARS security testing.

See [Phase 2: KARS considerations](06-kars-phase2.md).
