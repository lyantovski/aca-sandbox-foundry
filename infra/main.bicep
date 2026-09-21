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

@description('Existing AKS subnet Network Contributor role-assignment name. Leave empty to create the assignment.')
param existingAksSubnetRoleAssignmentName string = ''

@description('Existing Foundry project Monitoring Reader role-assignment name. Leave empty to create the assignment.')
param existingFoundryMonitoringRoleAssignmentName string = ''

@description('Foundry project Application Insights connection name. Set this to the portal-generated name when adopting an existing connection.')
param appInsightsProjectConnectionName string = 'appinsights-default'

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

@description('Foundry chat model capacity in thousands of tokens per minute.')
@minValue(1)
param chatDeploymentCapacity int = 100

@description('Per-subscription APIM model gateway token limit per minute.')
@minValue(1000)
param apimModelTokensPerMinute int = 100000

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
var roleNetworkContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
var roleMonitoringReader = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
var a2aAgentOrigins = [
  {
    name: 'research'
    displayName: 'Research A2A Agent'
    serviceUrl: 'http://10.40.15.240:8001'
  }
  {
    name: 'creator'
    displayName: 'Creator A2A Agent'
    serviceUrl: 'http://10.40.15.241:8002'
  }
  {
    name: 'podcaster'
    displayName: 'Podcaster A2A Agent'
    serviceUrl: 'http://10.40.15.242:8003'
  }
]

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

resource agcNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${environmentName}-vnet-agc-nsg-${location}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowInternetFrontend'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
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
          networkSecurityGroup: {
            id: agcNsg.id
          }
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
    publicNetworkAccess: 'Disabled'
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

resource blobPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobPrivateDnsZone
  name: '${environmentName}-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource storageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${environmentName}-storage-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[2].id
    }
    privateLinkServiceConnections: [
      {
        name: 'blob'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource storageBlobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storageBlobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
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
    capacity: chatDeploymentCapacity
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
      enablePrivateCluster: false
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

resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'aks'
}

resource aksSubnetAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(existingAksSubnetRoleAssignmentName)) {
  name: guid(aksSubnet.id, aks.id, 'aks-network-contributor')
  scope: aksSubnet
  properties: {
    principalId: aks.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleNetworkContributor
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

resource apimApplicationInsightsLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerType: 'applicationInsights'
    description: 'ACA Sandbox Content Factory gateway telemetry'
    isBuffered: true
    resourceId: appInsights.id
    credentials: {
      instrumentationKey: appInsights.properties.InstrumentationKey
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

resource foundryProjectAppInsightsAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(existingFoundryMonitoringRoleAssignmentName)) {
  name: guid(appInsights.id, foundryProject.id, 'monitoring-reader')
  scope: appInsights
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleMonitoringReader
  }
}

resource apimProjectConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
    parent: foundryProject
    name: '${environmentName}-apim'
    properties: {
      category: 'ApiManagement'
      target: apim.id
      authType: 'AAD'
      metadata: {
        gatewayUrl: 'https://${apim.name}.azure-api.net'
        sku: apimSkuName
    }
  }
}

resource appInsightsProjectConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: appInsightsProjectConnectionName
  properties: {
    category: 'AppInsights'
    target: appInsights.id
    #disable-next-line BCP036
    authType: 'ProjectManagedIdentity'
    isSharedToAll: false
    useWorkspaceManagedIdentity: false
    metadata: {
      ApiType: 'Azure'
      ApplicationInsightsConnectionString: appInsights.properties.ConnectionString
      ResourceId: appInsights.id
      displayName: appInsights.name
    }
  }
}

resource modelApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'model-gateway'
  properties: {
    displayName: 'Foundry Model Gateway'
    path: 'openai'
    protocols: [
      'https'
    ]
    serviceUrl: '${foundry.properties.endpoint}openai'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
  }
}

resource chatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: modelApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment}/chat/completions'
    templateParameters: [
      {
        name: 'deployment'
        type: 'string'
        required: true
        values: []
      }
    ]
    responses: []
  }
}

resource speechOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: modelApi
  name: 'audio-speech'
  properties: {
    displayName: 'Audio Speech'
    method: 'POST'
    urlTemplate: '/deployments/{deployment}/audio/speech'
    templateParameters: [
      {
        name: 'deployment'
        type: 'string'
        required: true
        values: []
      }
    ]
    responses: []
  }
}

resource modelApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: modelApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace('''
      <policies>
        <inbound>
          <base />
          <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="foundry-token" ignore-error="false" />
          <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["foundry-token"])</value>
          </set-header>
          <azure-openai-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="__APIM_MODEL_TPM__" estimate-prompt-tokens="true" />
          <azure-openai-emit-token-metric namespace="ACA Sandbox">
            <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
            <dimension name="API ID" value="@(context.Api.Id)" />
          </azure-openai-emit-token-metric>
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    ''', '__APIM_MODEL_TPM__', string(apimModelTokensPerMinute))
  }
}

resource modelApiApplicationInsightsDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: modelApi
  name: 'applicationinsights'
  properties: {
    loggerId: apimApplicationInsightsLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: false
    metrics: true
    operationNameFormat: 'Name'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
  }
}

resource modelApiSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'content-factory-model'
  properties: {
    displayName: 'ACA Sandbox Content Factory model access'
    scope: modelApi.id
    state: 'active'
    allowTracing: false
  }
}

resource agentApis 'Microsoft.ApiManagement/service/apis@2024-05-01' = [for agent in a2aAgentOrigins: {
    parent: apim
    name: 'agent-${agent.name}'
    properties: {
      displayName: agent.displayName
      path: 'agents/${agent.name}'
      protocols: [
        'https'
      ]
      serviceUrl: agent.serviceUrl
      subscriptionRequired: false
    }
  }]

resource agentHealthOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for (agent, i) in a2aAgentOrigins: {
    parent: agentApis[i]
    name: 'health'
    properties: {
      displayName: 'Health'
      method: 'GET'
      urlTemplate: '/health'
      responses: []
    }
  }]

resource agentCardOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for (agent, i) in a2aAgentOrigins: {
    parent: agentApis[i]
    name: 'agent-card'
    properties: {
      displayName: 'A2A Agent Card'
      method: 'GET'
      urlTemplate: '/.well-known/agent-card.json'
      responses: []
    }
  }]

resource agentA2aOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for (agent, i) in a2aAgentOrigins: {
    parent: agentApis[i]
    name: 'a2a'
    properties: {
      displayName: 'A2A'
      method: 'POST'
      urlTemplate: '/a2a'
      responses: []
    }
  }]

resource agentA2aRootOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for (agent, i) in a2aAgentOrigins: {
    parent: agentApis[i]
    name: 'a2a-root'
    properties: {
      displayName: 'A2A Root'
      method: 'POST'
      urlTemplate: '/'
      responses: []
    }
  }]

resource agentA2aRootPolicies 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = [for (agent, i) in a2aAgentOrigins: {
    parent: agentA2aRootOperations[i]
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: '''
        <policies>
          <inbound>
            <base />
            <rewrite-uri template="/a2a" copy-unmatched-params="true" />
          </inbound>
          <backend>
            <base />
          </backend>
          <outbound>
            <base />
          </outbound>
          <on-error>
            <base />
          </on-error>
        </policies>
      '''
    }
  }]

resource researchStatusOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
    parent: agentApis[0]
    name: 'status'
    properties: {
      displayName: 'Status'
      method: 'GET'
      urlTemplate: '/status'
      responses: []
    }
  }

  resource podcasterTaskStatusOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
    parent: agentApis[2]
    name: 'task-status'
    properties: {
      displayName: 'Task Status'
      method: 'GET'
      urlTemplate: '/tasks/{taskId}'
      templateParameters: [
        {
          name: 'taskId'
          type: 'string'
          required: true
          values: []
        }
      ]
      responses: []
    }
  }

  resource agentApiPolicies 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = [for (agent, i) in a2aAgentOrigins: {
    parent: agentApis[i]
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: '''
        <policies>
          <inbound>
            <base />
          </inbound>
          <backend>
            <forward-request timeout="600" />
          </backend>
          <outbound>
            <base />
          </outbound>
          <on-error>
            <base />
          </on-error>
        </policies>
      '''
    }
}]

resource agentApiApplicationInsightsDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = [for (agent, i) in a2aAgentOrigins: {
  parent: agentApis[i]
  name: 'applicationinsights'
  properties: {
    loggerId: apimApplicationInsightsLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: false
    metrics: true
    operationNameFormat: 'Name'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
  }
}]

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

resource foundryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: foundry
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
output apimModelApiId string = modelApi.id
output apimModelSubscriptionId string = modelApiSubscription.id
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
