// =============================================================================
// Banking AI Log Analytics Platform — Azure Infrastructure
// main.bicep
//
// Provisions the full Azure infrastructure stack:
//   - Azure Data Lake Storage Gen2 (bronze / silver / gold containers)
//   - Azure Synapse Analytics Workspace
//   - Synapse Spark Pool  (small, 3 nodes, autoscale to 10)
//   - Synapse Dedicated SQL Pool (DW100c)
//   - Azure Event Hubs Namespace + Hub
//   - Azure Key Vault
//   - Azure OpenAI Service (placeholder — model deployments managed separately)
//   - Role assignments: Synapse MSI → Storage Blob Data Contributor
//
// Parameters are injected at deployment time; no secrets are hardcoded.
// =============================================================================

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Deployment environment tag (dev | test | prod).')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short prefix prepended to all resource names to ensure global uniqueness (2-8 lowercase alphanumeric).')
@minLength(2)
@maxLength(8)
param prefix string = 'ailogs'

@description('Azure Active Directory object ID of the initial Key Vault administrator (e.g. a deployment service principal).')
param kvAdminObjectId string

@description('AAD tenant ID used for Key Vault access policies.')
param tenantId string = subscription().tenantId

@description('Number of Event Hub message retention days.')
@minValue(1)
@maxValue(7)
param eventHubRetentionDays int = 3

@description('Event Hub partition count.')
@minValue(2)
@maxValue(32)
param eventHubPartitionCount int = 8

@description('Synapse Dedicated SQL Pool performance level.')
param sqlPoolSku string = 'DW100c'

@description('Tags applied to every resource.')
param tags object = {
  environment: environment
  platform: 'ai-log-analytics'
  domain: 'banking'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var suffix = uniqueString(resourceGroup().id, prefix, environment)
var shortSuffix = substring(suffix, 0, 6)

var storageAccountName     = '${prefix}adls${shortSuffix}'
var synapseWorkspaceName   = '${prefix}-synapse-${environment}-${shortSuffix}'
var sparkPoolName          = 'sparkPoolSmall'
var sqlPoolName            = 'sqlPool${environment}'
var eventHubNamespaceName  = '${prefix}-evhns-${environment}-${shortSuffix}'
var eventHubName           = 'ai-log-events'
var keyVaultName           = '${prefix}-kv-${environment}-${shortSuffix}'
var openAiAccountName      = '${prefix}-oai-${environment}-${shortSuffix}'
var synapseStorageContainer = 'synapsefs'

// Storage containers that form the medallion architecture
var storageContainers = [
  'bronze'
  'silver'
  'gold'
  synapseStorageContainer
]

// Built-in role definition IDs
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ---------------------------------------------------------------------------
// ADLS Gen2 Storage Account
// ---------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true                // Hierarchical namespace = ADLS Gen2
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false       // Enforce AAD auth only
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// ADLS Gen2 blob service (needed to define containers)
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    isVersioningEnabled: true
  }
}

// Bronze / Silver / Gold / Synapse filesystem containers
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [
  for containerName in storageContainers: {
    parent: blobService
    name: containerName
    properties: {
      publicAccess: 'None'
    }
  }
]

// ---------------------------------------------------------------------------
// Azure Synapse Analytics Workspace
// ---------------------------------------------------------------------------

resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://${storageAccountName}.dfs.core.windows.net'
      filesystem: synapseStorageContainer
      resourceId: storageAccount.id
      createManagedPrivateEndpoint: false
    }
    sqlAdministratorLogin: 'synapseAdmin'
    // Password must be supplied at deploy time via --parameters or Key Vault reference;
    // never hardcode here.  Reference the Key Vault secret via parameter if needed.
    sqlAdministratorLoginPassword: ''   // Provide via secure parameter at deploy time
    managedVirtualNetwork: 'default'
    managedVirtualNetworkSettings: {
      preventDataExfiltration: true
      allowedAadTenantIdsForLinking: [
        tenantId
      ]
    }
    publicNetworkAccess: 'Enabled'
    azureADOnlyAuthentication: false
  }
}

// Allow Synapse Workspace to pass firewall for its own storage account
resource synapseFirewallAllowAzure 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ---------------------------------------------------------------------------
// Synapse Spark Pool (small cluster, autoscale 3 → 10 nodes)
// ---------------------------------------------------------------------------

resource sparkPool 'Microsoft.Synapse/workspaces/bigDataPools@2021-06-01' = {
  parent: synapseWorkspace
  name: sparkPoolName
  location: location
  tags: tags
  properties: {
    sparkVersion: '3.4'
    nodeSize: 'Small'
    nodeSizeFamily: 'MemoryOptimized'
    autoScale: {
      enabled: true
      minNodeCount: 3
      maxNodeCount: 10
    }
    autoPause: {
      enabled: true
      delayInMinutes: 15
    }
    dynamicExecutorAllocation: {
      enabled: true
      minExecutors: 1
      maxExecutors: 4
    }
    sparkConfigProperties: {
      configurationType: 'Artifact'
    }
    sessionLevelPackagesEnabled: true
  }
}

// ---------------------------------------------------------------------------
// Synapse Dedicated SQL Pool (DW100c)
// ---------------------------------------------------------------------------

resource sqlPool 'Microsoft.Synapse/workspaces/sqlPools@2021-06-01' = {
  parent: synapseWorkspace
  name: sqlPoolName
  location: location
  tags: tags
  sku: {
    name: sqlPoolSku
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    createMode: 'Default'
  }
}

// ---------------------------------------------------------------------------
// Role Assignment: Synapse MSI → Storage Blob Data Contributor on ADLS
// ---------------------------------------------------------------------------

resource synapseStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, synapseWorkspace.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataContributorRoleId
    )
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Grants the Synapse workspace managed identity read/write access to the ADLS Gen2 lakehouse storage account.'
  }
}

// ---------------------------------------------------------------------------
// Azure Event Hubs Namespace + Hub
// ---------------------------------------------------------------------------

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 2
  }
  properties: {
    disableLocalAuth: false
    isAutoInflateEnabled: true
    maximumThroughputUnits: 10
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: eventHubRetentionDays
    partitionCount: eventHubPartitionCount
    status: 'Active'
    captureDescription: {
      enabled: true
      encoding: 'Avro'
      intervalInSeconds: 300
      sizeLimitInBytes: 314572800
      destination: {
        name: 'EventHubArchive.AzureBlockBlob'
        properties: {
          storageAccountResourceId: storageAccount.id
          blobContainer: 'bronze'
          archiveNameFormat: '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}'
        }
      }
      skipEmptyArchives: true
    }
  }
}

// Consumer group for Synapse ingestion pipeline
resource eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2023-01-01-preview' = {
  parent: eventHub
  name: 'synapse-ingest-cg'
  properties: {}
}

// ---------------------------------------------------------------------------
// Azure Key Vault
// ---------------------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true     // Use RBAC rather than vault access policies
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Grant the initial admin Key Vault Administrator role via RBAC
// Role: Key Vault Administrator (00482a5a-887f-4fb3-b363-3b7fe8e74483)
resource kvAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, kvAdminObjectId, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '00482a5a-887f-4fb3-b363-3b7fe8e74483'
    )
    principalId: kvAdminObjectId
    principalType: 'ServicePrincipal'
    description: 'Initial Key Vault administrator role for the deployment service principal.'
  }
}

// Grant Synapse MSI Key Vault Secrets User so pipelines can read secrets
// Role: Key Vault Secrets User (4633458b-17de-408a-b874-0445c86b69e6)
resource synapseKvSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, synapseWorkspace.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows the Synapse workspace MSI to read secrets from Key Vault for linked service authentication.'
  }
}

// ---------------------------------------------------------------------------
// Azure OpenAI Service (placeholder — model deployments managed separately)
// ---------------------------------------------------------------------------

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openAiAccountName
  location: location   // Azure OpenAI is not available in all regions; adjust as needed
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAiAccountName
    networkAcls: {
      defaultAction: 'Allow'         // Tighten to Deny + VNet rules in production
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the ADLS Gen2 storage account.')
output storageAccountId string = storageAccount.id

@description('ADLS Gen2 DFS endpoint.')
output storageAccountDfsEndpoint string = storageAccount.properties.primaryEndpoints.dfs

@description('Resource ID of the Synapse Analytics workspace.')
output synapseWorkspaceId string = synapseWorkspace.id

@description('Synapse workspace development endpoint.')
output synapseDevEndpoint string = synapseWorkspace.properties.connectivityEndpoints.dev

@description('Synapse workspace SQL on-demand (serverless) endpoint.')
output synapseSqlOnDemandEndpoint string = synapseWorkspace.properties.connectivityEndpoints.sqlOnDemand

@description('Synapse Dedicated SQL Pool endpoint.')
output synapseSqlDedicatedEndpoint string = synapseWorkspace.properties.connectivityEndpoints.sql

@description('Resource ID of the Synapse Spark pool.')
output sparkPoolId string = sparkPool.id

@description('Resource ID of the Synapse Dedicated SQL Pool.')
output sqlPoolId string = sqlPool.id

@description('Event Hub Namespace FQDN.')
output eventHubNamespaceFqdn string = '${eventHubNamespaceName}.servicebus.windows.net'

@description('Event Hub name.')
output eventHubName string = eventHub.name

@description('Key Vault URI.')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Azure OpenAI endpoint.')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('Synapse workspace managed identity principal ID.')
output synapseMsiPrincipalId string = synapseWorkspace.identity.principalId
