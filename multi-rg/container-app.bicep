@description('Name of the project used to generate resource names')
param projectName string

@description('Location for all resources')
param location string

@description('Container app environment name')
param containerAppEnvName string

@description('Container app name')
param containerAppName string

@description('Container image to deploy')
param containerImage string

@description('Storage account name from the infra resource group')
param storageAccountName string

@description('Resource group name where storage account is deployed')
param storageAccountResourceGroup string

@description('File share name in the storage account')
param fileShareName string

@description('Container subnet ID from the infra resource group')
param containerSubnetId string

// Variables
var logAnalyticsWorkspaceName = '${projectName}-loganalytics'
var managedIdentityName = '${projectName}-mi'
var storageFileShareMountName = 'fileshare-mount'

// Resource references
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
  scope: resourceGroup(storageAccountResourceGroup)
}

// Log Analytics workspace for container app environment
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// User-assigned managed identity for container app
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

// Check if Container App Environment already exists
resource existingContainerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: containerAppEnvName
}

// Check if the environment exists
var containerAppEnvironmentExists = length(existingContainerAppEnvironment.?id ?? '') > 0

// Get Log Analytics shared key properly
var logAnalyticsSharedKey = logAnalyticsWorkspace.listKeys().primarySharedKey

// Get Storage account key properly  
var storageAccountKey = storageAccount.listKeys().keys[0].value

// Container Apps Environment - conditionally deploy based on existence
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    // Only include vnetConfiguration for new deployments
    vnetConfiguration: containerAppEnvironmentExists ? null : {
      infrastructureSubnetId: containerSubnetId
    }
    zoneRedundant: false
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['*']
        }
      }
      registries: []
    }
    template: {
      containers: [
        {
          image: containerImage
          name: 'nginx'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          volumeMounts: [
            {
              volumeName: storageFileShareMountName
              mountPath: '/usr/share/nginx/html'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: storageFileShareMountName
          storageType: 'AzureFile'
          storageName: storageFileShareMountName
        }
      ]
    }
  }
}

// Storage volume configuration for container app
// This uses the storage account from the infra resource group
resource containerAppStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  name: storageFileShareMountName
  parent: containerAppEnvironment
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccountKey
      shareName: fileShareName
      accessMode: 'ReadWrite'
    }
  }
}

// Outputs
output containerAppFQDN string = containerApp.properties.configuration.ingress.fqdn
output containerAppURL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
