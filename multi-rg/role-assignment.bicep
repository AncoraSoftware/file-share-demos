@description('Managed identity principal ID that needs access')
param principalId string

@description('Storage account name')
param storageAccountName string

@description('Role definition ID to assign to the managed identity')
param roleDefinitionId string = '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb' // Storage File Data SMB Share Contributor

@description('Storage account ID for RBAC permissions')
param storageAccountId string

// Resource references
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Storage account role assignment 
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, principalId, roleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Output the role assignment ID for reference
output roleAssignmentId string = roleAssignment.id
