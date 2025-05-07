@description('Name of the project used to generate resource names')
param projectName string = 'fs-demo-single-rg'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Storage account SKU')
param storageAccountSku string = 'Standard_LRS'

@description('File share name')
param fileShareName string = 'content'

@description('File share quota in GB')
param fileShareQuotaInGB int = 100

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix for storage')
param storageSubnetAddressPrefix string = '10.0.1.0/24'

@description('Subnet address prefix for container apps')
param containerSubnetAddressPrefix string = '10.0.2.0/23'

@description('Container app environment name')
param containerAppEnvName string = '${projectName}-env'

@description('Container app name')
param containerAppName string = '${projectName}-app'

@description('Container image to deploy')
param containerImage string = 'nginx:latest'

// Variables for unique naming and references
var storageAccountName = '${take(replace(toLower(projectName), '-', ''), 10)}sa${take(uniqueString(resourceGroup().id), 8)}'
var vnetName = '${projectName}-vnet'
var storageSubnetName = 'storage-subnet'
var containerSubnetName = 'container-subnet'
var logAnalyticsWorkspaceName = '${projectName}-loganalytics'
var managedIdentityName = '${projectName}-mi'
var storageFileShareMountName = 'fileshare-mount'

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

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// File Share
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {}
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: fileShareName
  parent: fileServices
  properties: {
    shareQuota: fileShareQuotaInGB
    enabledProtocols: 'SMB'
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: storageSubnetName
        properties: {
          addressPrefix: storageSubnetAddressPrefix
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [
                '*'
              ]
            }
          ]
        }
      }
      {
        name: containerSubnetName
        properties: {
          addressPrefix: containerSubnetAddressPrefix
        }
      }
    ]
  }
}

// Get references to the subnets
// resource storageSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' existing = {
//   name: storageSubnetName
//   parent: vnet
// }

resource containerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' existing = {
  name: containerSubnetName
  parent: vnet
}

// Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: containerSubnet.id
    }
    zoneRedundant: false
  }
}

// Storage account role assignment
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'storage-file-data-smb-share-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb') // Storage File Data SMB Share Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
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
    roleAssignment
  ]
}

// Storage volume configuration for container app
resource containerAppStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  name: storageFileShareMountName
  parent: containerAppEnvironment
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: fileShare.name
      accessMode: 'ReadWrite'
    }
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output fileShareName string = fileShare.name
output containerAppFQDN string = containerApp.properties.configuration.ingress.fqdn
output containerAppURL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
