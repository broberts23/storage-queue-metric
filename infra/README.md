# Infra and deployment

This folder contains a Bicep template to deploy:

- Storage account with six queues
- Application Insights
- Consumption Function App with system-assigned identity

Usage (local):

1. Deploy Bicep:
   az deployment group create --resource-group <rg> --template-file infra/main.bicep

2. Get deployment name (from az output) and run the scripts in `scripts/` to create and populate queues:
   pwsh ./scripts/create-queues.ps1 -ResourceGroup <rg> -DeploymentName <deploymentName>
   pwsh ./scripts/populate-queues.ps1 -ResourceGroup <rg> -DeploymentName <deploymentName> -MinMessages 1 -MaxMessages 100

GitHub Actions

- Workflow `.github/workflows/deploy.yml` uses `AZURE_CREDENTIALS` and `AZURE_RESOURCE_GROUP` secrets.
- It deploys the Bicep and then zips and deploys the function app from `QueueMessageCountToLA`.
