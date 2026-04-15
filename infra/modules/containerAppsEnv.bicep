// Azure Container Apps Environment with Workload Profiles
// Dedicated D4 profile: order-service, makeline-service (low-latency, user-facing)
// Consumption profile: all other services (scale-to-zero, event-driven)
targetScope = 'resourceGroup'

param name string
param location string = resourceGroup().location
param tags object = {}

param logAnalyticsWorkspaceName string
@secure()
param daprAIConnectionString string = ''

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource acaEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        #disable-next-line use-secure-value-for-secure-inputs
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    daprAIConnectionString: daprAIConnectionString
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'dedicated-d4'
        workloadProfileType: 'D4'
        minimumCount: 1
        maximumCount: 5
      }
    ]
    peerAuthentication: {
      mtls: {
        enabled: true
      }
    }
  }
}

output id string = acaEnvironment.id
output name string = acaEnvironment.name
output defaultDomain string = acaEnvironment.properties.defaultDomain
output staticIp string = acaEnvironment.properties.staticIp
