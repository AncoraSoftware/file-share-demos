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

@description('Storage subnet ID for network rules')
param containerSubnetId string

// Variables for unique naming
var storageAccountName = '${take(replace(toLower(projectName), '-', ''), 10)}sa${take(uniqueString(resourceGroup().id), 8)}'

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
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: containerSubnetId
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

