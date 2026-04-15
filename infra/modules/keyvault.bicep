// Azure Key Vault
// Stores secrets referenced by ACA container apps and Dapr components.
// All access is via RBAC (Key Vault Secrets User role) — vault access policies disabled.
targetScope = 'resourceGroup'

param name string
param location string = resourceGroup().location
param tags object = {}

// Secrets to seed on creation (App Insights connection string, etc.)
param secrets array = []
// e.g. [{ name: 'appinsights-connection-string', value: '...' }]

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource kvSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for secret in secrets: {
  parent: keyVault
  name: secret.name
  properties: {
    value: secret.value
  }
}]

output id string = keyVault.id
output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
