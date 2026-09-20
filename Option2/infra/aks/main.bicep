targetScope = 'resourceGroup'

@description('Short environment name used as the resource-name prefix.')
@minLength(5)
@maxLength(20)
param environmentName string

@description('Azure region. Verify AKS, AGC, Foundry model, APIM, and ACA Sandbox availability before deployment.')
param location string = resourceGroup().location

@description('Supported Kubernetes version. Revalidate against the selected KARS release before adopting KARS.')
param kubernetesVersion string = '1.35'

@description('System node VM size.')
param systemNodeVmSize string = 'Standard_D4as_v6'

@description('Agent node VM size.')
param agentNodeVmSize string = 'Standard_D4as_v6'

@description('Initial number of nodes in the agent pool.')
@minValue(1)
param agentNodeCount int = 2

@description('API Management SKU. Standard v2 provides the AI gateway and outbound VNet integration for private backends.')
param apimSkuName string = 'StandardV2'

@description('API Management capacity.')
@minValue(1)
param apimCapacity int = 1

@description('Publisher name required by API Management.')
param apimPublisherName string

@description('Publisher email required by API Management.')
param apimPublisherEmail string

@description('Object ID granted Azure Kubernetes Service RBAC Cluster Admin. Leave empty to skip the assignment.')
param aksAdminPrincipalId string = ''

@description('Globally unique Azure Container Registry name.')
@minLength(5)
@maxLength(50)
param acrName string = take('acr${replace(environmentName, '-', '')}cf', 50)

@description('Foundry chat model deployment name.')
param chatDeploymentName string = 'gpt-4o'

@description('Foundry chat model name.')
param chatModelName string = 'gpt-4o'

@description('Foundry chat model version.')
param chatModelVersion string = '2024-11-20'

@description('Deploy the optional TTS model.')
param deployTtsModel bool = true

@description('ACA Sandbox Group name.')
param sandboxGroupName string = '${environmentName}-sandbox-group'

@description('Tags applied to resources.')
param tags object = {
  solution: 'aca-sandbox-content-factory'
  environment: environmentName
  'kars-ready': 'true'
}

var compactName = toLower(replace(environmentName, '-', ''))
var aksName = '${environmentName}-aks'
var namespace = 'content-factory'
var roleAcrPull = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var roleStorageBlobDataContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var roleCognitiveServicesOpenAIUser = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
var roleSandboxGroupDataOwner = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'c24cf47c-5077-412d-a19c-45202126392c')
var roleAksRbacClusterAdmin = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${environmentName}-apim-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureKeyVaultOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${environmentName}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'aks'
        properties: {
          addressPrefix: '10.40.0.0/20'
        }
      }
      {
        name: 'agc'
        properties: {
          addressPrefix: '10.40.16.0/24'
          delegations: [
            {
              name: 'agc'
              properties: {
                serviceName: 'Microsoft.ServiceNetworking/trafficControllers'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.40.17.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'apim'
        properties: {
          addressPrefix: '10.40.18.0/24'
          networkSecurityGroup: {
            id: apimNsg.id
          }
          delegations: [
            {
              name: 'apim-vnet-integration'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${environmentName}-logs'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${environmentName}-appinsights'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: '${environmentName}-monitor'
  location: location
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('${compactName}kv', 24)
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('${compactName}store', 24)
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource podcastContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'podcasts'
  properties: {
    publicAccess: 'None'
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: '${environmentName}-foundry'
  location: location
  tags: tags
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: '${environmentName}-foundry'
    publicNetworkAccess: 'Enabled'
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundry
  name: '${environmentName}-project'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: foundry
  name: chatDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
  }
}

resource ttsDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployTtsModel) {
  parent: foundry
  name: 'tts-1'
  dependsOn: [
    chatDeployment
  ]
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'tts'
      version: '001'
    }
  }
}

resource sandboxIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${environmentName}-sandbox-uami'
  location: location
  tags: tags
}

resource sandboxGroup 'Microsoft.App/sandboxGroups@2026-02-01-preview' = {
  name: sandboxGroupName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sandboxIdentity.id}': {}
    }
  }
  properties: {
    imageRegistryCredentials: [
      {
        server: acr.properties.loginServer
        identity: sandboxIdentity.id
      }
    ]
  }
}

resource workloadIdentities 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [for workload in [
  'research'
  'creator'
  'podcaster'
  'bff'
  'sandbox-broker'
]: {
  name: '${environmentName}-${workload}-uami'
  location: location
  tags: union(tags, {
    component: workload
  })
}]

resource aks 'Microsoft.ContainerService/managedClusters@2025-05-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: tenant().tenantId
    }
    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: false
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricAnnotationsAllowList: ''
          metricLabelsAllowlist: ''
        }
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'cilium'
      networkDataplane: 'cilium'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      serviceCidr: '10.41.0.0/16'
      dnsServiceIP: '10.41.0.10'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: 2
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: vnet.properties.subnets[0].id
        enableAutoScaling: true
        minCount: 2
        maxCount: 4
      }
      {
        name: 'agents'
        mode: 'User'
        count: agentNodeCount
        vmSize: agentNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: vnet.properties.subnets[0].id
        enableAutoScaling: true
        minCount: 1
        maxCount: 6
        nodeLabels: {
          'workload.azure.com/type': 'agent'
          'kars.azure.com/pool': 'sandbox'
        }
        nodeTaints: [
          'workload.azure.com/type=agent:NoSchedule'
        ]
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
          useAADAuth: 'true'
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      azurepolicy: {
        enabled: true
      }
    }
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, 'acr-pull')
  scope: acr
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleAcrPull
  }
}

resource aksAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aksAdminPrincipalId)) {
  name: guid(aks.id, aksAdminPrincipalId, 'aks-rbac-cluster-admin')
  scope: aks
  properties: {
    principalId: aksAdminPrincipalId
    principalType: 'User'
    roleDefinitionId: roleAksRbacClusterAdmin
  }
}

resource federatedCredentials 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [for (workload, i) in [
  'research'
  'creator'
  'podcaster'
  'bff'
  'sandbox-broker'
]: {
  parent: workloadIdentities[i]
  name: '${workload}-federated'
  properties: {
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${namespace}:${workload}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}]

resource researchFoundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, workloadIdentities[0].id, 'openai-user')
  scope: foundry
  properties: {
    principalId: workloadIdentities[0].properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleCognitiveServicesOpenAIUser
  }
}

resource creatorFoundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, workloadIdentities[1].id, 'openai-user')
  scope: foundry
  properties: {
    principalId: workloadIdentities[1].properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleCognitiveServicesOpenAIUser
  }
}

resource podcasterFoundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, workloadIdentities[2].id, 'openai-user')
  scope: foundry
  properties: {
    principalId: workloadIdentities[2].properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleCognitiveServicesOpenAIUser
  }
}

resource podcasterStorageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, workloadIdentities[2].id, 'blob-contributor')
  scope: storage
  properties: {
    principalId: workloadIdentities[2].properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleStorageBlobDataContributor
  }
}

resource brokerSandboxAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sandboxGroup.id, workloadIdentities[4].id, 'sandbox-owner')
  scope: sandboxGroup
  properties: {
    principalId: workloadIdentities[4].properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleSandboxGroupDataOwner
  }
}

resource sandboxAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, sandboxIdentity.id, 'sandbox-acr-pull')
  scope: acr
  properties: {
    principalId: sandboxIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleAcrPull
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: '${environmentName}-apim'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: apimSkuName
    capacity: apimCapacity
  }
  properties: {
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: vnet.properties.subnets[3].id
    }
  }
}

resource apimFoundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, apim.id, 'apim-openai-user')
  scope: foundry
  properties: {
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleCognitiveServicesOpenAIUser
  }
}

resource trafficController 'Microsoft.ServiceNetworking/trafficControllers@2025-01-01' = {
  name: '${environmentName}-agc'
  location: location
  tags: tags
}

resource trafficControllerAssociation 'Microsoft.ServiceNetworking/trafficControllers/associations@2025-01-01' = {
  parent: trafficController
  name: 'aks'
  location: location
  properties: {
    associationType: 'subnets'
    subnet: {
      id: vnet.properties.subnets[1].id
    }
  }
}

resource trafficControllerFrontend 'Microsoft.ServiceNetworking/trafficControllers/frontends@2025-01-01' = {
  parent: trafficController
  name: 'public'
  location: location
}

resource aksDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: aks
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: apim
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: keyVault
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource acrDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: acr
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource blobDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: blobService
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

output aksName string = aks.name
output aksResourceId string = aks.id
output acrLoginServer string = acr.properties.loginServer
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString
output applicationInsightsName string = appInsights.name
output azureMonitorWorkspaceId string = monitorWorkspace.id
output foundryEndpoint string = foundry.properties.endpoint
output foundryProjectName string = foundryProject.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output applicationGatewayForContainersId string = trafficController.id
output applicationGatewayFrontendId string = trafficControllerFrontend.id
output applicationGatewayFrontendFqdn string = trafficControllerFrontend.properties.fqdn
output sandboxGroupResourceId string = sandboxGroup.id
output storageAccountName string = storage.name
output workloadIdentityClientIds object = {
  research: workloadIdentities[0].properties.clientId
  creator: workloadIdentities[1].properties.clientId
  podcaster: workloadIdentities[2].properties.clientId
  bff: workloadIdentities[3].properties.clientId
  sandboxBroker: workloadIdentities[4].properties.clientId
}
