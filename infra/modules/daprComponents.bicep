// Dapr Components registered in the Azure Container Apps Environment
// - pubsub-servicebus : Azure Service Bus (managed identity, no SAS keys)
// - statestore-redis  : Azure Cache for Redis (TLS, access-key auth)
// - statestore-cosmosdb: Azure Cosmos DB NoSQL (managed identity)
targetScope = 'resourceGroup'

param environmentName string

@description('Service Bus namespace name (without .servicebus.windows.net suffix)')
param serviceBusNamespace string

@description('Redis cache hostname')
param redisHost string

@description('Redis primary access key')
@secure()
param redisPassword string

@description('Cosmos DB account endpoint URL')
param cosmosEndpoint string

param cosmosDatabase string
param cosmosContainer string

@description('Client ID of the user-assigned managed identity used by all services')
param managedIdentityClientId string

resource acaEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

// ── Service Bus pub/sub ───────────────────────────────────────────────────────
resource pubsubServiceBus 'Microsoft.App/managedEnvironments/daprComponents@2024-03-01' = {
  name: 'pubsub-servicebus'
  parent: acaEnvironment
  properties: {
    componentType: 'pubsub.azure.servicebus.topics'
    version: 'v1'
    metadata: [
      { name: 'namespaceName', value: '${serviceBusNamespace}.servicebus.windows.net' }
      { name: 'azureClientId', value: managedIdentityClientId }
    ]
    scopes: [
      'order-service'
      'makeline-service'
      'accounting-service'
      'loyalty-service'
      'receipt-service'
    ]
  }
}

// ── Redis state store ─────────────────────────────────────────────────────────
resource statestoreRedis 'Microsoft.App/managedEnvironments/daprComponents@2024-03-01' = {
  name: 'statestore-redis'
  parent: acaEnvironment
  properties: {
    componentType: 'state.redis'
    version: 'v1'
    secrets: [
      { name: 'redis-password', value: redisPassword }
    ]
    metadata: [
      { name: 'redisHost', value: '${redisHost}:6380' }
      { name: 'redisPassword', secretRef: 'redis-password' }
      { name: 'enableTLS', value: 'true' }
    ]
    scopes: [
      'makeline-service'
    ]
  }
}

// ── Cosmos DB state store ─────────────────────────────────────────────────────
resource statestoreCosmosDb 'Microsoft.App/managedEnvironments/daprComponents@2024-03-01' = {
  name: 'statestore-cosmosdb'
  parent: acaEnvironment
  properties: {
    componentType: 'state.azure.cosmosdb'
    version: 'v1'
    metadata: [
      { name: 'url', value: cosmosEndpoint }
      { name: 'database', value: cosmosDatabase }
      { name: 'collection', value: cosmosContainer }
      { name: 'azureClientId', value: managedIdentityClientId }
    ]
    scopes: [
      'loyalty-service'
    ]
  }
}
