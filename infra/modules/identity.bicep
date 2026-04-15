// Provisions a User-Assigned Managed Identity and all RBAC role assignments
// needed by the Red Dog microservices to access Azure resources without secrets.
targetScope = 'resourceGroup'

param name string
param location string = resourceGroup().location
param tags object = {}

// Resource IDs for RBAC scope assignments
param serviceBusNamespaceId string = ''
param cosmosAccountId string = ''
param storageAccountId string = ''
param keyVaultId string = ''
param acrId string = ''

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

// ── Service Bus ──────────────────────────────────────────────────────────────
// Azure Service Bus Data Owner allows send + receive + manage
resource sbDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(serviceBusNamespaceId)) {
  name: guid(identity.id, serviceBusNamespaceId, 'ServiceBusDataOwner')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Service Bus Data Owner for Red Dog services'
  }
}

// ── Cosmos DB ─────────────────────────────────────────────────────────────────
// Cosmos DB Built-in Data Contributor
resource cosmosDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(cosmosAccountId)) {
  name: guid(identity.id, cosmosAccountId, 'CosmosDataContributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Cosmos DB Data Contributor for loyalty-service'
  }
}

// ── Storage ───────────────────────────────────────────────────────────────────
// Storage Blob Data Contributor for Dapr output binding (receipts)
resource storageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(storageAccountId)) {
  name: guid(identity.id, storageAccountId, 'StorageBlobDataContributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Storage Blob Data Contributor for receipt-service Dapr binding'
  }
}

// ── Key Vault ─────────────────────────────────────────────────────────────────
// Key Vault Secrets User — read secrets at runtime
resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(keyVaultId)) {
  name: guid(identity.id, keyVaultId, 'KeyVaultSecretsUser')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Key Vault Secrets User for all services'
  }
}

// ── ACR ───────────────────────────────────────────────────────────────────────
// ACR Pull — allows ACA to pull images
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrId)) {
  name: guid(identity.id, acrId, 'AcrPull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'ACR Pull for all container apps'
  }
}

output identityId string = identity.id
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
