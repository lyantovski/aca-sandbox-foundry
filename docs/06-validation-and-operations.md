# 6. Validation and Operations

## Static validation

Run the repository validator without application tests:

```powershell
.\deploy\validate.ps1 -SkipTests
```

Run the complete validation, including all application test suites:

```powershell
.\deploy\validate.ps1
```

The underlying infrastructure and chart checks can also be run individually:

```powershell
az bicep build --file .\infra\main.bicep
helm lint .\deploy\helm\content-factory `
  -f .\deploy\helm\content-factory\values.example.yaml
```

Run the existing agent test suites:

```powershell
python -m pytest .\src\agent-research\tests
python -m pytest .\src\agent-podcaster\tests
python -m pytest .\src\bff\tests
python -m pytest .\src\sandbox-broker\tests
dotnet test .\src\agent-creator\AgentCreator.Tests\AgentCreator.Tests.csproj
```

## Cluster checks

```powershell
kubectl -n content-factory get deploy,pod,svc,gateway,httproute
kubectl -n content-factory get events --sort-by=.lastTimestamp
kubectl -n content-factory rollout status deploy/agent-research
kubectl -n content-factory rollout status deploy/agent-creator
kubectl -n content-factory rollout status deploy/agent-podcaster
kubectl -n content-factory rollout status deploy/bff
kubectl -n content-factory rollout status deploy/sandbox-broker
```

## Required acceptance tests

1. Unauthenticated DevUI API requests are rejected.
2. Browser source, storage, and network logs contain no reusable downstream credential.
3. Agent Services have no public load balancer.
4. Requests that bypass APIM are rejected.
5. All health and A2A endpoints work through the governed path.
6. Foundry discovers every agent card and invokes every agent.
7. Research succeeds through the sandbox broker.
8. The research-agent identity cannot create an ACA Sandbox directly.
9. Disallowed sandbox egress is blocked and visible in telemetry.
10. Podcast audio is written with workload identity and anonymous access fails.
11. A request can be traced through AGC, BFF, APIM, an agent, model calls, broker, and ACA Sandbox.
12. OTLP exporter failure and dropped telemetry trigger an alert.

## Telemetry

Application code sends OTLP to the in-cluster Collector. Azure platform resources use diagnostic settings. Avoid duplicate container-log ingestion.

Minimum dashboards:

- Workflow request rate, success rate, and latency.
- Agent A2A request latency and errors.
- Model calls, tokens, throttles, and content-safety decisions.
- Sandbox creation, execution, denied egress, and cleanup.
- APIM and AGC health.
- AKS pod, node, and network health.
- Collector queue, retry, and dropped-telemetry health.

Telemetry destinations:

- Research, creator, podcaster, BFF, and sandbox broker send OTLP to the
  in-cluster Collector and then to `aca-sandbox-appinsights`.
- APIM sends correlated request, dependency, exception, and custom token
  metrics for the model API and three stable agent APIs to the same Application
  Insights component.
- Foundry/model resource diagnostics, APIM platform diagnostics, AKS control
  plane logs, and container logs go to `aca-sandbox-logs`.
- DevUI is static NGINX; its platform/container logs are collected, but it does
  not run an application telemetry SDK.

Never enable prompt or response capture by default. Redact tokens, cookies, authorization headers, prompts, generated content, and customer data.

## Visual acceptance evidence

![Completed three-agent DevUI workflow](media/devui-overview.png)

The overview shows all three agents healthy and a completed research, content,
and podcast run through the authenticated DevUI.

<table>
  <tr>
    <td width="50%">
      <img src="media/devui-sandboxes-content.png"
           alt="ACA Sandbox lifecycle, egress evidence, research brief, and generated content">
    </td>
    <td width="50%">
      <img src="media/devui-podcast.png"
           alt="Generated social posts, playable podcast, and transcript">
    </td>
  </tr>
  <tr>
    <td>Sandbox lifecycle and egress evidence are visible beside the synthesized research brief and generated content.</td>
    <td>The final output includes social posts, browser-playable podcast audio, and the host-and-guest transcript.</td>
  </tr>
</table>

## Live validation record

Validated on September 21, 2026:

- Helm release `content-factory` is deployed and every container is Ready.
- All containers use numeric non-root UIDs, restricted capabilities, disabled
  privilege escalation, and `RuntimeDefault` seccomp.
- AGC Gateway and HTTPRoute are accepted and programmed.
- DevUI returns HTTP 200; protected API requests redirect to Microsoft Entra ID.
- APIM chat completions returned HTTP 200 through `gpt-4o`.
- APIM reached all three stable private agent origins and returned HTTP 200.
- The BFF uses the Foundry-governed URLs
  `https://aca-sandbox-apim.azure-api.net/{name}-agent` rather than calling
  stable APIM APIs or ClusterIP services directly.
- A full research A2A request completed through BFF, APIM, the private research
  origin, and ACA Sandbox in 216 seconds with HTTP 200.
- Creator completed through APIM with HTTP 200.
- Podcaster accepted an asynchronous request with HTTP 202 and its APIM polling
  route reached `completed` with generated audio.
- The sandbox broker returned HTTP 200 for a live ACA Sandbox fetch.
- Application Insights contains request and dependency telemetry exported
  through the in-cluster OTEL Collector.
- The existing `aca-sandbox-apim` instance is associated with Foundry as the AI
  Gateway; no second APIM instance was created.
- `research-agent`, `creator-agent`, and `podcaster-agent` are registered as
  **Custom**, **Active** A2A assets for `aca-sandbox-project`.
- All three generated cards return HTTP 200 and advertise their governed base
  URLs.
- Creator completed through the governed `/creator-agent/a2a` route with HTTP
  200. Podcaster returned HTTP 202 through its governed base URL, and
  `/podcaster-agent/tasks/{taskId}` returned HTTP 200 until the task reached
  `completed`.

Sandboxes are created on demand for each research request. After execution, the
broker returns the fetch result, retains the sandboxes in a tracked background
cleanup task for `config.sandboxRetentionSeconds` (60 seconds in the deployed
demo), and then deletes them. A live validation returned the broker response in
4.7 seconds while the sandbox remained listed, then confirmed zero active
sandboxes after cleanup. This short, configurable window makes active instances
visible in the Sandbox Group portal without holding the A2A response open or
leaving demo sandboxes running indefinitely. Broker logs emit
`lifecycle=created`, `lifecycle=retaining`, `lifecycle=deleting`, and
`lifecycle=deleted` with each sandbox ID.

One sandbox intentionally attempts to reach `bing.com`, which is not included
in its allowlist. This is a deliberate egress-control demonstration, not a
research dependency. The sandbox policy uses `default_action=Deny`, so Bing is
normally absent from the configured host rules.

Interpret the evidence carefully:

- A Bing entry returned by `get_egress_decisions()` is a confirmed Sandbox
  policy denial.
- A request exception or HTTP 403 without a matching decision is inferred
  failure evidence and must not be described as a confirmed policy decision.
- A successful Bing request is a policy violation and must never be displayed
  as blocked.

The current DevUI wording should preserve this distinction whenever the backend
provides the evidence type.

Foundry Control Plane registration required an authenticated Foundry (new)
portal session. The generated governed URLs are:

- `https://aca-sandbox-apim.azure-api.net/research-agent`
- `https://aca-sandbox-apim.azure-api.net/creator-agent`
- `https://aca-sandbox-apim.azure-api.net/podcaster-agent`

Each stable API includes a root POST compatibility operation that rewrites to
`/a2a`. This is required because generated cards advertise the governed base
URL. Registering the base URL also keeps sibling routes, especially podcaster
task polling, reachable through the governed path.

Application Insights telemetry is working through direct OTLP export. The
Foundry project has an `AppInsights` connection targeting
`aca-sandbox-appinsights` with project managed identity, and the project
identity retains **Monitoring Reader** without weakening policy. The existing
portal-created connection is adopted in Bicep through
`appInsightsProjectConnectionName`.

Verify the connection after deployment:

1. Open **Foundry > aca-sandbox-project > Monitoring > Application
   analytics** and confirm `aca-sandbox-appinsights` is connected.
2. Confirm the project connection category is `AppInsights`, authentication is
   `ProjectManagedIdentity`, and the target is the
   `aca-sandbox-appinsights` resource ID.
3. Confirm Application analytics lists telemetry for `research-agent`,
   `creator-agent`, `podcaster-agent`, `content-factory-bff`,
   `sandbox-broker`, and APIM after a workflow.
4. Confirm the project managed identity retains **Monitoring Reader** on
   `aca-sandbox-appinsights`.
