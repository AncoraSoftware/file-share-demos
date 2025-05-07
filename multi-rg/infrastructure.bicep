@description('Name of the project used to generate resource names')
param projectName string

@description('Location for all resources')
param location string

@description('Storage account SKU')
param storageAccountSku string

@description('File share name')
param fileShareName string

@description('File share quota in GB')
param fileShareQuotaInGB int

@description('Virtual network address prefix')
param vnetAddressPrefix string

@description('Subnet address prefix for storage')
param storageSubnetAddressPrefix string

@description('Subnet address prefix for container apps')
param containerSubnetAddressPrefix string

@description('Container app environment name')
param containerAppEnvName string

// Variables for unique naming
var storageAccountName = '${take(replace(toLower(projectName), '-', ''), 10)}sa${take(uniqueString(resourceGroup().id), 8)}'
var vnetName = '${projectName}-vnet'
var storageSubnetName = 'storage-subnet'
var containerSubnetName = 'container-subnet'
var logAnalyticsWorkspaceName = '${projectName}-loganalytics'

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

// Container Apps Environment - conditionally deploy based on existence
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
      infrastructureSubnetId: '${vnet.id}/subnets/${containerSubnetName}'
    }
    zoneRedundant: false
  }
}

// Storage Account with explicit dependency on subnet
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
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: '${vnet.id}/subnets/${containerSubnetName}'
          action: 'Allow'
        }
      ]
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

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output fileShareName string = fileShare.name
output fileShareId string = fileShare.id
output vnetName string = vnet.name
output vnetId string = vnet.id
