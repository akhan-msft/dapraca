// Red Dog Order Management — Main Bicep Orchestrator
// Provisions all Azure resources and deploys all 7 Container Apps
// Usage: azd up  OR  az deployment group create --template-file main.bicep --parameters main.parameters.json
targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g. dev, test, prod). Used to generate unique resource names.')
param environmentName string

@minLength(1)
@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Object ID of the identity that runs deployments — used as SQL Active Directory admin.')
param deploymentPrincipalId string = ''

// ── Container image tags (set by CI/CD pipeline) ─────────────────────────────
param uiImageTag string = 'latest'
param orderServiceImageTag string = 'latest'
param accountingServiceImageTag string = 'latest'
param loyaltyServiceImageTag string = 'latest'
param makelineServiceImageTag string = 'latest'
param receiptServiceImageTag string = 'latest'
param bootstrapImageTag string = 'latest'

// ── Naming helpers ────────────────────────────────────────────────────────────
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(resourceGroup().id, environmentName))
var tags = { 'azd-env-name': environmentName, project: 'dapraca', 'managed-by': 'bicep' }

// ── Resource names ────────────────────────────────────────────────────────────
var names = {
  identity: '${abbrs['Microsoft.ManagedIdentity/userAssignedIdentities']}-reddog-${resourceToken}'
  logAnalytics: '${abbrs['Microsoft.OperationalInsights/workspaces']}-reddog-${resourceToken}'
  appInsights: '${abbrs['Microsoft.Insights/components']}-reddog-${resourceToken}'
  acr: '${abbrs['Microsoft.ContainerRegistry/registries']}reddog${resourceToken}'
  keyVault: '${abbrs['Microsoft.KeyVault/vaults']}-reddog-${resourceToken}'
  serviceBus: '${abbrs['Microsoft.ServiceBus/namespaces']}-reddog-${resourceToken}'
  cosmos: '${abbrs['Microsoft.DocumentDB/databaseAccounts']}-reddog-${resourceToken}'
  sql: '${abbrs['Microsoft.Sql/servers']}-reddog-${resourceToken}'
  redis: '${abbrs['Microsoft.Cache/redis']}-reddog-${resourceToken}'
  storage: '${abbrs['Microsoft.Storage/storageAccounts']}reddog${resourceToken}'
  acaEnv: '${abbrs['Microsoft.App/managedEnvironments']}-reddog-${resourceToken}'
}

// ── Monitoring ────────────────────────────────────────────────────────────────
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    workspaceName: names.logAnalytics
    appInsightsName: names.appInsights
    location: location
    tags: tags
  }
}

// ── Container Registry ────────────────────────────────────────────────────────
module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    name: names.acr
    location: location
    tags: tags
  }
}

// ── Service Bus ───────────────────────────────────────────────────────────────
module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  params: {
    namespaceName: names.serviceBus
    location: location
    tags: tags
  }
}

// ── Cosmos DB ─────────────────────────────────────────────────────────────────
module cosmos 'modules/cosmosdb.bicep' = {
  name: 'cosmosdb'
  params: {
    accountName: names.cosmos
    location: location
    tags: tags
  }
}

// ── Managed Identity (created early — before Key Vault, so KV can ref its ID) ─
// Note: RBAC role assignments that need keyVaultId/acrId are deferred to identity-rbac
module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: names.identity
    location: location
    tags: tags
  }
}

// ── Azure SQL ─────────────────────────────────────────────────────────────────
module sql 'modules/sql.bicep' = {
  name: 'sql'
  params: {
    serverName: names.sql
    location: location
    tags: tags
    adminObjectId: !empty(deploymentPrincipalId) ? deploymentPrincipalId : identity.outputs.principalId
  }
}

// ── Redis ─────────────────────────────────────────────────────────────────────
module redis 'modules/redis.bicep' = {
  name: 'redis'
  params: {
    name: names.redis
    location: location
    tags: tags
  }
}

// ── Storage ───────────────────────────────────────────────────────────────────
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: names.storage
    location: location
    tags: tags
  }
}

// ── Key Vault (seeded with secrets) ──────────────────────────────────────────
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: names.keyVault
    location: location
    tags: tags
    secrets: [
      { name: 'appinsights-connection-string', value: monitoring.outputs.appInsightsConnectionString }
      { name: 'redis-host', value: redis.outputs.hostName }
      { name: 'redis-password', value: redis.outputs.primaryKey }
      { name: 'sql-server-fqdn', value: sql.outputs.serverFqdn }
      { name: 'sql-database-name', value: sql.outputs.databaseName }
      { name: 'servicebus-namespace', value: serviceBus.outputs.endpoint }
      { name: 'cosmos-endpoint', value: cosmos.outputs.endpoint }
    ]
  }
}

// ── RBAC role assignments (after all resources exist) ─────────────────────────
module identityRbac 'modules/identity.bicep' = {
  name: 'identity-rbac'
  params: {
    name: names.identity   // references the same identity resource (idempotent)
    location: location
    tags: tags
    serviceBusNamespaceId: serviceBus.outputs.id
    cosmosAccountId: cosmos.outputs.id
    storageAccountId: storage.outputs.id
    keyVaultId: keyVault.outputs.id
    acrId: acr.outputs.id
  }
  #disable-next-line no-unnecessary-dependson
  dependsOn: [identity]
}

// ── ACA Environment ───────────────────────────────────────────────────────────
module acaEnv 'modules/containerAppsEnv.bicep' = {
  name: 'acaEnvironment'
  params: {
    name: names.acaEnv
    location: location
    tags: tags
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    daprAIConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// ── Shared env vars injected into every container app ────────────────────────
var commonEnv = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    secretRef: 'appinsights-connection-string'
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: identity.outputs.clientId
  }
]

var commonSecrets = [
  {
    name: 'appinsights-connection-string'
    keyVaultUrl: '${keyVault.outputs.uri}secrets/appinsights-connection-string'
    identity: identity.outputs.identityId
  }
]

// ── Bootstrap Service (Python) ────────────────────────────────────────────────
module bootstrap 'modules/containerApp.bicep' = {
  name: 'bootstrap'
  params: {
    name: 'bootstrap'
    location: location
    tags: union(tags, { 'azd-service-name': 'bootstrap' })
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/bootstrap:${bootstrapImageTag}'
    workloadProfileName: 'Consumption'
    ingressType: 'none'
    daprEnabled: false
    userAssignedIdentityId: identity.outputs.identityId
    minReplicas: 0
    maxReplicas: 1
    env: union(commonEnv, [
      { name: 'SQL_SERVER', secretRef: 'sql-server-fqdn' }
      { name: 'SQL_DATABASE', secretRef: 'sql-database-name' }
    ])
    secrets: union(commonSecrets, [
      {
        name: 'sql-server-fqdn'
        keyVaultUrl: '${keyVault.outputs.uri}secrets/sql-server-fqdn'
        identity: identity.outputs.identityId
      }
      {
        name: 'sql-database-name'
        keyVaultUrl: '${keyVault.outputs.uri}secrets/sql-database-name'
        identity: identity.outputs.identityId
      }
    ])
  }
}

// ── Order Service (Java) — Dedicated D4 ──────────────────────────────────────
module orderService 'modules/containerApp.bicep' = {
  name: 'order-service'
  params: {
    name: 'order-service'
    location: location
    tags: union(tags, { 'azd-service-name': 'order-service' })
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/order-service:${orderServiceImageTag}'
    workloadProfileName: 'dedicated-d4'
    ingressType: 'internal'
    daprEnabled: true
    daprAppId: 'order-service'
    userAssignedIdentityId: identity.outputs.identityId
    cpuCores: '1.0'
    memoryGi: '2Gi'
    minReplicas: 1
    maxReplicas: 10
    scaleRules: [
      {
        name: 'http-scale'
        http: { metadata: { concurrentRequests: '50' } }
      }
    ]
    env: commonEnv
    secrets: commonSecrets
  }
}

// ── Accounting Service (Java) — Consumption ───────────────────────────────────
module accountingService 'modules/containerApp.bicep' = {
  name: 'accounting-service'
  params: {
    name: 'accounting-service'
    location: location
    tags: union(tags, { 'azd-service-name': 'accounting-service' })
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/accounting-service:${accountingServiceImageTag}'
    workloadProfileName: 'Consumption'
    ingressType: 'internal'
    daprEnabled: true
    daprAppId: 'accounting-service'
    userAssignedIdentityId: identity.outputs.identityId
    minReplicas: 0
    maxReplicas: 10
    scaleRules: [
      {
        name: 'servicebus-scale'
        custom: {
          type: 'azure-servicebus'
          metadata: {
            namespace: serviceBus.outputs.name
            topicName: 'orders'
            subscriptionName: 'accounting-service'
            messageCount: '10'
          }
          auth: [
            {
              secretRef: 'azure-client-id-placeholder'
              triggerParameter: 'clientId'
            }
          ]
        }
      }
      {
        name: 'http-scale'
        http: { metadata: { concurrentRequests: '30' } }
      }
    ]
    env: union(commonEnv, [
      { name: 'SQL_SERVER', secretRef: 'sql-server-fqdn' }
      { name: 'SQL_DATABASE', secretRef: 'sql-database-name' }
    ])
    secrets: union(commonSecrets, [
      {
        name: 'sql-server-fqdn'
        keyVaultUrl: '${keyVault.outputs.uri}secrets/sql-server-fqdn'
        identity: identity.outputs.identityId
      }
      {
        name: 'sql-database-name'
        keyVaultUrl: '${keyVault.outputs.uri}secrets/sql-database-name'
        identity: identity.outputs.identityId
      }
    ])
  }
}

// ── Loyalty Service (Java) — Consumption ─────────────────────────────────────
module loyaltyService 'modules/containerApp.bicep' = {
  name: 'loyalty-service'
  params: {
    name: 'loyalty-service'
    location: location
    tags: union(tags, { 'azd-service-name': 'loyalty-service' })
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/loyalty-service:${loyaltyServiceImageTag}'
    workloadProfileName: 'Consumption'
    ingressType: 'internal'
    daprEnabled: true
    daprAppId: 'loyalty-service'
    userAssignedIdentityId: identity.outputs.identityId
    minReplicas: 0
    maxReplicas: 10
    scaleRules: [
      {
        name: 'servicebus-scale'
        custom: {
          type: 'azure-servicebus'
          metadata: {
            namespace: serviceBus.outputs.name
            topicName: 'orders'
            subscriptionName: 'loyalty-service'
            messageCount: '10'
          }
        }
      }
    ]
    env: commonEnv
    secrets: commonSecrets
  }
}

// ── Makeline Service (Java) — Dedicated D4 ───────────────────────────────────
module makelineService 'modules/containerApp.bicep' = {
  name: 'makeline-service'
  params: {
    name: 'makeline-service'
    location: location
    tags: union(tags, { 'azd-service-name': 'makeline-service' })
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/makeline-service:${makelineServiceImageTag}'
    workloadProfileName: 'dedicated-d4'
    ingressType: 'internal'
    daprEnabled: true
    daprAppId: 'makeline-service'
    userAssignedIdentityId: identity.outputs.identityId
    cpuCores: '1.0'
    memoryGi: '2Gi'
    minReplicas: 1
    maxReplicas: 10
    scaleRules: [
      {
        name: 'servicebus-scale'
        custom: {
          type: 'azure-servicebus'
          metadata: {
            namespace: serviceBus.outputs.name
            topicName: 'orders'
            subscriptionName: 'makeline-service'
            messageCount: '10'
          }
        }
      }
      {
        name: 'http-scale'
        http: { metadata: { concurrentRequests: '50' } }
      }
    ]
    env: commonEnv
    secrets: commonSecrets
  }
}

// ── Receipt Service (.NET 8) — Consumption ────────────────────────────────────
module receiptService 'modules/containerApp.bicep' = {
  name: 'receipt-service'
  params: {
    name: 'receipt-service'
    location: location
    tags: union(tags, { 'azd-service-name': 'receipt-service' })
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/receipt-service:${receiptServiceImageTag}'
    workloadProfileName: 'Consumption'
    ingressType: 'internal'
    daprEnabled: true
    daprAppId: 'receipt-service'
    userAssignedIdentityId: identity.outputs.identityId
    minReplicas: 0
    maxReplicas: 10
    scaleRules: [
      {
        name: 'servicebus-scale'
        custom: {
          type: 'azure-servicebus'
          metadata: {
            namespace: serviceBus.outputs.name
            topicName: 'orders'
            subscriptionName: 'receipt-service'
            messageCount: '10'
          }
        }
      }
    ]
    env: commonEnv
    secrets: commonSecrets
  }
}

// ── UI Service (ReactJS + Node.js BFF) — External ingress ────────────────────
module ui 'modules/containerApp.bicep' = {
  name: 'ui'
  params: {
    name: 'ui'
    location: location
    tags: union(tags, { 'azd-service-name': 'ui' })
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/ui:${uiImageTag}'
    containerPort: 3000
    workloadProfileName: 'Consumption'
    ingressType: 'external'
    daprEnabled: true
    daprAppId: 'ui'
    daprAppPort: 3000
    userAssignedIdentityId: identity.outputs.identityId
    minReplicas: 1
    maxReplicas: 10
    scaleRules: [
      {
        name: 'http-scale'
        http: { metadata: { concurrentRequests: '100' } }
      }
    ]
    env: union(commonEnv, [
      { name: 'DAPR_HTTP_PORT', value: '3500' }
      { name: 'ORDER_SERVICE_APP_ID', value: 'order-service' }
      { name: 'ACCOUNTING_SERVICE_APP_ID', value: 'accounting-service' }
      { name: 'MAKELINE_SERVICE_APP_ID', value: 'makeline-service' }
    ])
    secrets: commonSecrets
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_URI string = keyVault.outputs.uri
output APP_INSIGHTS_NAME string = monitoring.outputs.appInsightsName
output UI_URL string = 'https://${ui.outputs.fqdn}'
output ACA_ENVIRONMENT_NAME string = acaEnv.outputs.name
output SERVICE_BUS_NAMESPACE string = serviceBus.outputs.name
