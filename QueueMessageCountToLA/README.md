
# QueueMessageCountToLA Azure Function

This PowerShell 7.4 Azure Function enumerates all queues in a specified storage account, queries the QueueMessageCount metric per-queue using Az.Monitor, and sends the current counts to a Log Analytics workspace using the Data Collector API.

Configuration (set as Application Settings or in local.settings.json):

- LA_WORKSPACE_ID: Log Analytics workspace ID
- LA_WORKSPACE_KEY: Primary or Secondary key for the workspace
- AZURE_SUBSCRIPTION_ID: subscription id containing the storage account
- STORAGE_RESOURCE_GROUP: resource group of the storage account
- STORAGE_ACCOUNT_NAME: storage account name

KQL Example (to create a tile showing queue name and message count):

QueueMessageCount
| summarize LatestMessageCount = max(MessageCount) by QueueName
| project QueueName, LatestMessageCount
| order by LatestMessageCount desc

Deploy: zip and deploy to Azure Functions or use Azure CLI / Azure Functions Core Tools.
