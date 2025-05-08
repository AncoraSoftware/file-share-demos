@description('Name of the project used to generate resource names')
param projectName string

@description('Location for all resources')
param location string

@description('Virtual network address prefix')
param vnetAddressPrefix string

@description('Subnet address prefix for storage')
param storageSubnetAddressPrefix string

@description('Subnet address prefix for container apps')
param containerSubnetAddressPrefix string

// Variables
var vnetName = '${projectName}-vnet'
var logAnalyticsWorkspaceName = '${projectName}-law'
var storageSubnetName = 'storage-subnet'
var containerSubnetName = 'container-subnet'

// Log Analytics Workspace for Container App Environment
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
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
        }
      }
      {
        name: containerSubnetName
        properties: {
          addressPrefix: containerSubnetAddressPrefix
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
    ]
  }
}

// Outputs
output vnetName string = vnet.name
output vnetId string = vnet.id
output storageSubnetId string = vnet.properties.subnets[0].id
output containerSubnetId string = vnet.properties.subnets[1].id
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
