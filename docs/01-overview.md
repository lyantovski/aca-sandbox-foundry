# 1. Solution Overview

## Purpose

The Agentic Content Factory demonstrates a governed, observable multi-agent
workflow on AKS while keeping untrusted web retrieval inside Azure Container
Apps Sandboxes.

The design has five goals:

- Run independent polyglot A2A agents on AKS.
- Govern agent and model access through APIM AI Gateway.
- Register governed agent endpoints as Microsoft Foundry assets.
- Isolate research execution with deny-by-default sandbox egress.
- Provide end-to-end telemetry in Application Insights.

## User workflow

![Execution flow](diagrams/execution-flow.svg)

1. The authenticated user submits a topic in DevUI.
2. The research agent discovers and ranks sources.
3. The research agent groups selected URLs and requests sandboxes through the
   broker.
4. Sandboxes fetch only allowed source domains and return content plus egress
   evidence.
5. The creator agent produces a blog and social content.
6. The podcaster agent creates a conversation, synthesizes audio, and persists
   it to private Blob Storage.
7. DevUI displays the final content and the real sandbox lifecycle.

## Phase 1 scope

Phase 1 includes:

- AKS with OIDC, Workload Identity, Azure RBAC, Cilium, restricted Pod
  Security, and separate system and agent node pools.
- Application Gateway for Containers and Entra-authenticated DevUI access.
- APIM Standard v2 as the model and A2A gateway.
- Microsoft Foundry model deployment, project integration, and custom-agent
  registration.
- ACA Sandbox Group access through a least-privileged broker.
- Private Blob Storage access.
- OpenTelemetry, Application Insights, Log Analytics, and Azure Monitor.

Phase 1 does not include KARS. See
[KARS Phase 2 considerations](09-kars-phase2.md).

## Important demo characteristics

- The AKS API server is public for lab operation; production must use private
  AKS.
- The current AGC endpoint uses a self-signed certificate; production requires
  a trusted certificate and custom DNS name.
- One sandbox performs an intentional Bing egress-control test. It is not a
  research dependency.
- The application creates at most five sandboxes per research workflow. This
  application cap is separate from Azure Sandbox service quota.
- Sandboxes remain visible for a configured retention interval after execution
  and are then deleted asynchronously.

## Next steps

Follow [Architecture and components](02-architecture.md), then
[Network design](03-network-design.md) before deploying the environment.

