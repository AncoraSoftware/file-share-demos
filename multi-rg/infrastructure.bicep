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

// Variables for unique naming
var storageAccountName = '${take(replace(toLower(projectName), '-', ''), 10)}sa${take(uniqueString(resourceGroup().id), 8)}'
var vnetName = '${projectName}-vnet'
var storageSubnetName = 'storage-subnet'
var containerSubnetName = 'container-subnet'

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

// Get references to the subnets for outputs
resource containerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' existing = {
  name: containerSubnetName
  parent: vnet
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output fileShareName string = fileShare.name
output fileShareId string = fileShare.id
output vnetName string = vnet.name
output vnetId string = vnet.id
output containerSubnetId string = containerSubnet.id
