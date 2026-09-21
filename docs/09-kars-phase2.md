# 9. Phase 2: KARS Considerations

KARS is not part of Phase 1. Phase 1 produces a measurable baseline that Phase 2 can compare against.

## Phase 1 comparison baseline

![Phase 1 architecture baseline](diagrams/system-architecture.editable-preview.svg)

KARS evaluation starts from the working architecture above. Any Phase 2 change
must identify which AKS runtime, APIM, model, sandbox, storage, identity, or
telemetry connector it replaces or inserts into and must preserve a tested
rollback to this baseline.

## Phase 1 prerequisites retained for KARS

- AKS OIDC and workload identity.
- Kubernetes 1.30 or later for the current admission policies.
- Azure CNI powered by Cilium as the current KARS reference path.
- Dedicated labelled and tainted agent node pool.
- Key Vault CSI and ACR.
- Default-deny network policy and an explicit destination inventory.
- Application Insights, Container Insights, and Prometheus.
- Stable APIM A2A URLs and Foundry registrations.
- ACA Sandbox access isolated behind the broker.

## Is Cilium mandatory?

The KARS Helm resources use standard Kubernetes NetworkPolicy objects, so Cilium is not a mechanical installation requirement. The current KARS AKS Bicep explicitly deploys Azure CNI with Cilium, however, and parts of its documented policy behavior are validated against that dataplane.

Using another network-policy implementation requires a separate support and security test. It must prove default-deny egress, router-only external access, DNS, AgentMesh, APIM/model, OTLP, Storage, and broker traffic, including negative lateral-movement tests.

## Phase 2 changes

1. Install pinned KARS CRDs, controller, inference router, egress guard, A2A gateway, and AgentMesh components.
2. Convert each agent Deployment to a `KarsSandbox` or supported BYO runtime.
3. Route model access through the KARS inference router and APIM.
4. Permit the sandbox broker as an explicit KARS tool/service destination.
5. Move egress policy from learning to strict enforcement.
6. Revalidate APIM A2A import, Foundry registration, identity propagation, and trace correlation.

## Go/no-go gates

- KARS supports the exact AKS/Kubernetes/Cilium versions.
- APIM and KARS agree on A2A card and JSON-RPC behavior.
- APIM-to-KARS caller identity is cryptographically verified.
- The KARS inference router authenticates to the APIM model endpoint.
- Strict egress allows required traffic and rejects negative tests.
- ACA Sandbox operations continue only through the broker.
- Performance remains within the Phase 1 baseline.
- Rollback to conventional Deployments is tested.

## Current maturity caution

KARS is evolving rapidly. Pin the release and images by digest, review its maturity document, and treat public A2A ingress, APIM integration, token audiences, and operational dashboards as integration work rather than turnkey guarantees.

References:

- https://github.com/Azure/kars
- https://github.com/Azure/kars/blob/main/docs/getting-started.md
- https://github.com/Azure/kars/blob/main/docs/maturity.md
