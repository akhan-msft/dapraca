// Reusable Container App module
// Supports external/internal/none ingress, Dapr sidecar, KEDA scale rules,
// workload profile selection, and managed identity assignment.
targetScope = 'resourceGroup'

param name string
param location string = resourceGroup().location
param tags object = {}

param environmentId string
param containerImage string
param containerPort int = 8080
param workloadProfileName string = 'Consumption'

// Ingress
@allowed(['external', 'internal', 'none'])
param ingressType string = 'internal'

// Identity
param userAssignedIdentityId string

// ACR login server — always set separately so registries auth uses ACR, not placeholder image host
param acrLoginServer string = ''

// Dapr
param daprEnabled bool = true
param daprAppId string = name
param daprAppPort int = containerPort

// Environment variables
param env array = []
// e.g. [{ name: 'MY_VAR', value: '...' }, { name: 'SECRET_VAR', secretRef: 'my-secret' }]

// Secrets (Key Vault references)
param secrets array = []
// e.g. [{ name: 'my-secret', keyVaultUrl: 'https://...', identity: identityId }]

// Resources
param cpuCores string = '0.5'
param memoryGi string = '1Gi'

// KEDA scale rules
param scaleRules array = []
param minReplicas int = 0
param maxReplicas int = 10

resource containerApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: workloadProfileName
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: ingressType == 'none' ? null : {
        external: ingressType == 'external'
        targetPort: containerPort
        transport: 'http'
        allowInsecure: false
        corsPolicy: ingressType == 'external' ? {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
          allowedHeaders: ['*']
        } : null
      }
      dapr: daprEnabled ? {
        enabled: true
        appId: daprAppId
        appPort: daprAppPort
        appProtocol: 'http'
        enableApiLogging: false
        logLevel: 'info'
      } : {
        enabled: false
      }
      secrets: secrets
      registries: empty(acrLoginServer) ? [] : [
        {
          identity: userAssignedIdentityId
          server: acrLoginServer
        }
      ]
    }
    template: {
      containers: [
        {
          name: name
          image: containerImage
          resources: {
            cpu: json(cpuCores)
            memory: memoryGi
          }
          env: env
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: scaleRules
      }
    }
  }
}

output id string = containerApp.id
output name string = containerApp.name
output fqdn string = ingressType != 'none' ? containerApp.properties.configuration.ingress.fqdn : ''
output latestRevisionName string = containerApp.properties.latestRevisionName
