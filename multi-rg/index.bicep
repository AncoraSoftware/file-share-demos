targetScope = 'subscription'

@description('Name of the project used to generate resource names')
param projectName string = 'fs-demo-multi-rg'

@description('Location for all resources')
param location string = deployment().location

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

// Resource group for infrastructure resources (storage, networking)
resource mainResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${projectName}-main-rg'
  location: location
}

// Resource group for container app and related resources
resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${projectName}-storage-rg'
  location: location
}

// Deploy shared storage module
module storageModule 'shared-storage.bicep' = {
    name: 'sharedStorageDeployment'
    scope: storageResourceGroup
    params: {
      projectName: projectName
      location: location
      storageAccountSku: storageAccountSku
      fileShareName: fileShareName
      fileShareQuotaInGB: fileShareQuotaInGB
      containerSubnetId: infraModule.outputs.containerSubnetId
    }
  }

// Deploy shared infrastructure module (vnet, log analytics)
module infraModule 'shared-infrastructure.bicep' = {
  name: 'sharedInfra'
  scope: mainResourceGroup
  params: {
    projectName: projectName
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    storageSubnetAddressPrefix: storageSubnetAddressPrefix
    containerSubnetAddressPrefix: containerSubnetAddressPrefix
  }
}

// Deploy container app module
module containerAppModule 'container-apps.bicep' = {
  name: 'containerAppDeployment'
  scope: mainResourceGroup
  params: {
    projectName: projectName
    location: location
    containerAppName: containerAppName
    containerAppEnvName: containerAppEnvName
    containerImage: containerImage
    containerSubnetId: infraModule.outputs.containerSubnetId
    logAnalyticsWorkspaceId: infraModule.outputs.logAnalyticsWorkspaceId
    storageAccountId: storageModule.outputs.storageAccountId
    fileShareName: storageModule.outputs.fileShareName
  }
}

// module uploadFileShareData 'upload-file-share-data.bicep' = {
//   name: 'uploadFileShareData'
//   scope: storageResourceGroup
//   params: {
//     projectName: projectName
//     location: location
//     storageAccountName: storageModule.outputs.storageAccountName
//     fileShareName: storageModule.outputs.fileShareName
//   }
// }

// Outputs
output storageAccountName string = storageModule.outputs.storageAccountName
output fileShareName string = storageModule.outputs.fileShareName
output vnetName string = infraModule.outputs.vnetName
output containerAppFQDN string = containerAppModule.outputs.containerAppFQDN
output containerAppURL string = containerAppModule.outputs.containerAppURL
output storageResourceGroupName string = storageResourceGroup.name
output mainResourceGroupName string = mainResourceGroup.name
