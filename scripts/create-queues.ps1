param(
    [string]$ResourceGroup = $(throw 'ResourceGroup is required'),
    [string]$DeploymentName = $(throw 'DeploymentName is required')
)

$out = az deployment group show --resource-group $ResourceGroup --name $DeploymentName --query properties.outputs -o json | ConvertFrom-Json
$storageName = $out.storageAccount.value
$queues = $out.queueNames.value

Write-Host "Creating queues in storage account: $storageName"

$conn = az storage account show-connection-string --resource-group $ResourceGroup --name $storageName -o tsv

foreach ($q in $queues) {
    Write-Host "Creating queue: $q"
    az storage queue create --name $q --connection-string $conn | Out-Null
}

Write-Host "Created $($queues.Count) queues."
