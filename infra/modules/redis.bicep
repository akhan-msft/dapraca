// Azure Cache for Redis — used by makeline-service via Dapr state store
targetScope = 'resourceGroup'

param name string
param location string = resourceGroup().location
param tags object = {}

@description('Principal ID of the managed identity to grant Redis Data Owner access')
param managedIdentityPrincipalId string = ''

@description('Display name / alias for the access policy assignment')
param managedIdentityAlias string = ''

resource redis 'Microsoft.Cache/redis@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Standard'
      family: 'C'
      capacity: 1        // C1 Standard — suitable for demo; upgrade to C2+ for load testing
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
      'aad-enabled': 'true'
    }
    publicNetworkAccess: 'Enabled'
  }
  zones: []
}

// Grant Data Owner access policy to the managed identity for Entra ID auth
resource redisAccessPolicy 'Microsoft.Cache/redis/accessPolicyAssignments@2024-03-01' = if (!empty(managedIdentityPrincipalId)) {
  parent: redis
  name: 'mi-data-owner'
  properties: {
    accessPolicyName: 'Data Owner'
    objectId: managedIdentityPrincipalId
    objectIdAlias: !empty(managedIdentityAlias) ? managedIdentityAlias : 'managed-identity'
  }
}

output id string = redis.id
output name string = redis.name
output hostName string = redis.properties.hostName
output sslPort int = redis.properties.sslPort
