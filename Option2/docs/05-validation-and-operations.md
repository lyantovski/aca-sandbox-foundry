# 5. Validation and Operations

## Static validation

```powershell
az bicep build --file .\Option2\infra\aks\main.bicep
helm lint .\Option2\deploy\helm\content-factory `
  -f .\Option2\deploy\helm\content-factory\values.example.yaml
```

Run the existing agent test suites:

```powershell
python -m pytest .\Option2\Lab\src\agent-research\tests
python -m pytest .\Option2\Lab\src\agent-podcaster\tests
dotnet test .\Option2\Lab\src\agent-creator\AgentCreator.Tests\AgentCreator.Tests.csproj
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

Never enable prompt or response capture by default. Redact tokens, cookies, authorization headers, prompts, generated content, and customer data.

