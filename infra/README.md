# AKS Infrastructure

This directory contains the active infrastructure entry point for the Agentic
Content Factory lab.

The template provisions the KARS-ready AKS foundation, ACR, Key Vault, Storage, Application Insights, Log Analytics, Azure Monitor workspace, Foundry resources and models, APIM, Application Gateway for Containers, workload identities, and an ACA Sandbox Group.

It does not install KARS.

Validate:

```powershell
az bicep build --file .\main.bicep
```

Deploy:

```powershell
.\deploy.ps1 `
  -EnvironmentName aca-sandbox `
  -ResourceGroup aca-sandbox-content-factory-rg `
  -Location swedencentral `
  -ApimPublisherName "Platform Team" `
  -ApimPublisherEmail "platform@example.com"
```

The repository's active `azure.yaml` also points to this template, so `azd provision` can be used after setting `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`, `AZURE_PRINCIPAL_ID`, `APIM_PUBLISHER_NAME`, and `APIM_PUBLISHER_EMAIL` in the azd environment.

After deployment, install the workload Helm chart and complete the portal-only
configuration described in [Deployment](../docs/04-deployment.md) and
[Manual configuration](../docs/05-manual-configuration.md).
