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

// Variables

var managedIdentityName = '${projectName}-mi'
var storageFileShareMountName = 'fileshare-mount'
var containerAppEnvironmentId = resourceId('Microsoft.App/managedEnvironments', containerAppEnvName)

// Resource references
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
  scope: resourceGroup(storageAccountResourceGroup)
}

// User-assigned managed identity for container app
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
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
    environmentId: containerAppEnvironmentId
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
  name: '${containerAppEnvName}/${storageFileShareMountName}'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: fileShareName
      accessMode: 'ReadWrite'
    }
  }
}

// Storage account role assignment
// resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//     name: guid(resourceGroup().id, storageAccount.id, managedIdentity.id, smbShareContributorRoleDefinitionId)
//     scope: storageAccount
//     properties: {
//       roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', smbShareContributorRoleDefinitionId)
//       principalId: managedIdentity.properties.principalId
//       principalType: 'ServicePrincipal'
//     }
//   }

// Outputs
output containerAppFQDN string = containerApp.properties.configuration.ingress.fqdn
output containerAppURL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
