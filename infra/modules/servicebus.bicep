// Azure Service Bus — Standard tier (supports topics/subscriptions)
// Used as the Dapr Pub/Sub broker for the 'orders' topic
targetScope = 'resourceGroup'

param namespaceName string
param location string = resourceGroup().location
param tags object = {}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: true   // Enforce managed identity; no SAS keys
  }
}

// Orders topic — published by order-service, consumed by 4 services
resource ordersTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'orders'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    enableBatchedOperations: true
    enablePartitioning: false
  }
}

// Subscriptions — one per consuming service
var subscriptions = ['accounting-service', 'loyalty-service', 'makeline-service', 'receipt-service']

resource orderSubscriptions 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = [for sub in subscriptions: {
  parent: ordersTopic
  name: sub
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    enableBatchedOperations: true
    deadLetteringOnMessageExpiration: true
  }
}]

output id string = serviceBusNamespace.id
output name string = serviceBusNamespace.name
output endpoint string = '${serviceBusNamespace.name}.servicebus.windows.net'
output topicName string = ordersTopic.name
