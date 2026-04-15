// Azure Cache for Redis — used by makeline-service via Dapr state store
targetScope = 'resourceGroup'

param name string
param location string = resourceGroup().location
param tags object = {}

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
    }
    publicNetworkAccess: 'Enabled'
  }
  zones: []
}

output id string = redis.id
output name string = redis.name
output hostName string = redis.properties.hostName
output sslPort int = redis.properties.sslPort
@secure()
output primaryKey string = redis.listKeys().primaryKey
