param(
    [string]$ResourceGroup = $(throw 'ResourceGroup is required'),
    [string]$DeploymentName = $(throw 'DeploymentName is required'),
    [int]$MinMessages = 1,
    [int]$MaxMessages = 50
)

$out = az deployment group show --resource-group $ResourceGroup --name $DeploymentName --query properties.outputs -o json | ConvertFrom-Json
$storageName = $out.storageAccount.value
$queues = $out.queueNames.value

$conn = az storage account show-connection-string --resource-group $ResourceGroup --name $storageName -o tsv

foreach ($q in $queues) {
    $count = Get-Random -Minimum $MinMessages -Maximum ($MaxMessages + 1)
    Write-Host "Adding $count messages to queue: $q"
    for ($i = 0; $i -lt $count; $i++) {
        $msg = "msg-$(Get-Random -Minimum 100000 -Maximum 999999)"
        az storage message put --queue-name $q --content $msg --connection-string $conn | Out-Null
    }
}

Write-Host "Populated queues."
