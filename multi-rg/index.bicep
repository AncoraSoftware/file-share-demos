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
resource infraResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${projectName}-infra-rg'
  location: location
}

// Resource group for container app and related resources
resource appResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${projectName}-app-rg'
  location: location
}

// Deploy infrastructure module (storage account, vnet)
module infraModule 'infrastructure.bicep' = {
  name: 'infraDeployment'
  scope: infraResourceGroup
  params: {
    projectName: projectName
    location: location
    storageAccountSku: storageAccountSku
    fileShareName: fileShareName
    fileShareQuotaInGB: fileShareQuotaInGB
    vnetAddressPrefix: vnetAddressPrefix
    storageSubnetAddressPrefix: storageSubnetAddressPrefix
    containerSubnetAddressPrefix: containerSubnetAddressPrefix
  }
}

// Deploy container app module
module containerAppModule 'container-app.bicep' = {
  name: 'containerAppDeployment'
  scope: appResourceGroup
  params: {
    projectName: projectName
    location: location
    containerAppEnvName: containerAppEnvName
    containerAppName: containerAppName
    containerImage: containerImage
    storageAccountName: infraModule.outputs.storageAccountName
    storageAccountResourceGroup: infraResourceGroup.name
    fileShareName: infraModule.outputs.fileShareName
    containerSubnetId: infraModule.outputs.containerSubnetId
  }
}

// Deploy role assignment module to the infra resource group
// This allows the container app's managed identity to access the storage account
module roleAssignmentModule 'role-assignment.bicep' = {
  name: 'roleAssignmentDeployment'
  scope: infraResourceGroup
  params: {
    principalId: containerAppModule.outputs.managedIdentityPrincipalId
    storageAccountName: infraModule.outputs.storageAccountName
    storageAccountId: infraModule.outputs.storageAccountId
  }
}

// Outputs
output storageAccountName string = infraModule.outputs.storageAccountName
output fileShareName string = infraModule.outputs.fileShareName
output vnetName string = infraModule.outputs.vnetName
output containerAppFQDN string = containerAppModule.outputs.containerAppFQDN
output containerAppURL string = containerAppModule.outputs.containerAppURL
output infraResourceGroupName string = infraResourceGroup.name
output appResourceGroupName string = appResourceGroup.name
