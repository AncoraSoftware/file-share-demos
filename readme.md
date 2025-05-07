# Azure File Share mounting demos

## Single-resource group deployment 

This is the baseline deployment which is as simple as possible.

```bash
az group create --name fs-demo-single-rg --location southcentralus
az deployment group create --resource-group fs-demo-single-rg --template-file single-rg/main.bicep
```

## Multi-resource group deployment
 
Split storage into its own RG to simulate real-world deployment complexities

```bash
az deployment sub create --location southcentralus --template-file multi-rg/index.bicep
```