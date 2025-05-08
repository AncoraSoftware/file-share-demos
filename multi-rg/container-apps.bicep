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

@description('Storage account resource ID')
param storageAccountId string

@description('File share name in the storage account')
param fileShareName string

@description('Container subnet ID for the container app environment')
param containerSubnetId string 

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

// Variables
var managedIdentityName = '${projectName}-mi'
var storageFileShareMountName = 'fileshare-mount'
var storageAccountName = last(split(storageAccountId, '/'))

// User-assigned managed identity for container app
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

// Container App Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: containerSubnetId
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
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
  dependsOn: [
    containerAppStorage
  ]
}

// Storage volume configuration for container app
resource containerAppStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  name: '${containerAppEnvironment.name}/${storageFileShareMountName}'
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: listKeys(storageAccountId, '2023-01-01').keys[0].value
      shareName: fileShareName
      accessMode: 'ReadWrite'
    }
  }
}

// Outputs
output containerAppFQDN string = containerApp.properties.configuration.ingress.fqdn
output containerAppURL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppEnvironmentId string = containerAppEnvironment.id
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
