@description('Name of the project used to generate resource names')
param projectName string

@description('Location for all resources')
param location string

@description('Storage account name where the file share will be created')
param storageAccountName string

@description('File share name')
param fileShareName string

// Reference to existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Reference to existing file share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' existing = {
  name: '${storageAccount.name}/default/${fileShareName}'
}

var deploymentScriptName = '${projectName}-upload-script'
var managedIdentityName = '${projectName}-upload-identity'

// User-assigned managed identity for deployment script
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
    name: managedIdentityName
    location: location
  }
  
  // Role assignment - Storage File Data SMB Share Contributor on the storage account
  resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name: guid(resourceGroup().id, managedIdentity.id, 'contributor')
    scope: storageAccount
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb') // Storage File Data SMB Share Contributor role
      principalId: managedIdentity.properties.principalId
      principalType: 'ServicePrincipal'
    }
  }
  
  // Deployment script to upload the HTML file to the file share
  resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
    name: deploymentScriptName
    location: location
    kind: 'AzurePowerShell'
    identity: {
      type: 'UserAssigned'
      userAssignedIdentities: {
        '${managedIdentity.id}': {}
      }
    }
    properties: {
      azPowerShellVersion: '7.0'
      timeout: 'PT30M'
      retentionInterval: 'P1D'
      environmentVariables: [
        {
          name: 'AZURE_STORAGE_ACCOUNT'
          value: storageAccount.name
        }
        {
          name: 'FILE_SHARE_NAME'
          value: fileShare.name
        }
        {
          name: 'HTML_CONTENT'
          value: loadFileAsBase64('../index.html')
        }
      ]
      scriptContent: '''
        # Wait for role assignment to propagate
        Start-Sleep -Seconds 30
  
        # Convert HTML content from base64
        $htmlContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($env:HTML_CONTENT))
        
        # Create a temporary file
        $tempFile = New-TemporaryFile
        Set-Content -Path $tempFile -Value $htmlContent
        
        # Upload the file to the file share - directly to the root
        $ctx = New-AzStorageContext -StorageAccountName $env:AZURE_STORAGE_ACCOUNT -UseConnectedAccount
        Set-AzStorageFileContent -Context $ctx -ShareName $env:FILE_SHARE_NAME -Source $tempFile -Path "index.html" -Force
        
        # Clean up
        Remove-Item -Path $tempFile -Force
        
        $DeploymentScriptOutputs = @{}
        $DeploymentScriptOutputs['fileUploaded'] = "index.html uploaded to $env:FILE_SHARE_NAME/"
      '''
    }
    dependsOn: [
      roleAssignment
    ]
  }
  
  output fileUploaded string = deploymentScript.properties.outputs.fileUploaded
