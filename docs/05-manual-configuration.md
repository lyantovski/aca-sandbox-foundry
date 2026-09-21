# 5. Manual Configuration

This document contains the steps that cannot be completed reliably by the
current Bicep and Helm deployment. Complete them after
[Deployment](04-deployment.md).

## 1. Entra application for DevUI

Create or reuse an Entra application registration for oauth2-proxy:

1. Add the AGC callback URI:
   `https://<devui-hostname>/oauth2/callback`.
2. Create a client secret.
3. Record the tenant ID and client ID in the private Helm values file.
4. Store the client secret and a random 32-byte cookie secret in the referenced
   Kubernetes Secret or production secret store.

Do not commit either secret.

## 2. Trusted DevUI TLS

AGC provides a frontend FQDN but does not issue a trusted managed certificate.
The current lab uses a self-signed Kubernetes TLS Secret.

For a trusted endpoint:

1. Choose a custom DNS name.
2. Point its record to the AGC frontend.
3. Obtain a certificate covering that name.
4. Create or synchronize the Kubernetes TLS Secret.
5. Set `gateway.hostname` and `gateway.certificateSecretName`.
6. Add the final hostname as an Entra redirect URI.

Azure Front Door in front of AGC is an alternative trusted public frontend.

## 3. Associate APIM as the Foundry AI Gateway

In Foundry:

1. Open the Foundry resource and project.
2. Select **Manage > AI Gateway > Add AI Gateway**.
3. Select **Use existing APIM**.
4. Choose the APIM instance deployed by Bicep.
5. Associate the Foundry project.
6. Confirm the project gateway status is enabled.

Do not create a second APIM instance.

## 4. Connect Application Insights

In the Foundry project:

1. Open **Manage > Project details > Connected resources**.
2. Add the deployed Application Insights component.
3. Use **Project managed identity**.
4. Confirm the project identity has Monitoring Reader on Application Insights.

If the portal creates the initial connection, capture its resource name and pass
it as `appInsightsProjectConnectionName` on later Bicep deployments so the
template adopts rather than duplicates it.

## 5. Register the three Foundry assets

Register each agent under **Operate > Assets** with source **Custom** and
protocol **A2A**.

| Asset | Agent URL | Agent card |
|---|---|---|
| `research-agent` | `https://<apim-host>/research-agent` | `https://<apim-host>/research-agent/.well-known/agent-card.json` |
| `creator-agent` | `https://<apim-host>/creator-agent` | `https://<apim-host>/creator-agent/.well-known/agent-card.json` |
| `podcaster-agent` | `https://<apim-host>/podcaster-agent` | `https://<apim-host>/podcaster-agent/.well-known/agent-card.json` |

Use the stable governed base URL, not the private origin and not a URL ending in
`/a2a`. Enter the matching OTEL service name for each asset.

Asset registration is currently an authenticated Foundry control-plane action
and is intentionally documented rather than represented as a fake deployment
success.

## 6. Runtime secrets

The Helm chart references an existing Secret. The lab secret requires:

- A2A authentication token
- Sandbox broker token
- OAuth client secret
- OAuth cookie secret
- Any temporary model compatibility credential still required by the selected
  APIM policy

Production should synchronize these from Key Vault through the CSI driver.

## 7. Post-configuration checks

- Sign in to DevUI and confirm the real user appears in the account menu.
- Confirm APIM appears as the project AI Gateway.
- Confirm all three custom agents are active in Foundry.
- Confirm Foundry Application Analytics shows the shared Application Insights
  component.
- Invoke every agent through its APIM-governed URL.
- Replace the self-signed certificate before treating the endpoint as
  production-ready.

