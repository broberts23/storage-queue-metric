@description('Main Bicep to deploy Storage account, six queues, Application Insights and Function App')
param functionAppName string = toLower('queuemetricsfunc${uniqueString(resourceGroup().id)}')
param storageAccountName string = ''
param location string = resourceGroup().location

var defaultStorageName = toLower('st${substring(uniqueString(resourceGroup().id), 0, 12)}')
var finalStorageName = empty(storageAccountName) ? defaultStorageName : toLower(storageAccountName)

// generate six queue names (lowercase, short)
var queueNames = [for i in range(1, 7): toLower('q${substring(uniqueString(resourceGroup().id, string(i)), 0, 12)}')]

resource st 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: finalStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
  }
}

// Build connection strings and content share name after storage account exists
var storageAccountKey = st.listKeys().keys[0].value
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${st.name};AccountKey=${storageAccountKey};EndpointSuffix=${environment().suffixes.storage}'
var contentShareName = toLower('${functionAppName}-content')

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2021-09-01' = {
  name: 'default'
  parent: st
}

resource queues 'Microsoft.Storage/storageAccounts/queueServices/queues@2021-09-01' = [
  for q in queueNames: {
    name: q
    parent: queueService
    properties: {}
  }
]

// Ensure a file share exists for Function App content (required when using Azure Files content share settings)
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2021-09-01' = {
  name: 'default'
  parent: st
}

resource contentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-09-01' = {
  name: contentShareName
  parent: fileService
  properties: {}
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: toLower('${functionAppName}-ai')
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource plan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: toLower('${functionAppName}-plan')
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
}

resource functionApp 'Microsoft.Web/sites@2021-02-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id

    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: contentShareName
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: st.name
        }
        {
          name: 'STORAGE_RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'AZURE_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
      ]
    }
  }
  dependsOn: [queues, contentShare]
}

output queueNames array = queueNames
output storageAccount string = st.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output functionAppName string = functionApp.name
