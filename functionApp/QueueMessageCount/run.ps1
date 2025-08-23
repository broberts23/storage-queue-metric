param($Timer)

Write-Host "QueueMessageCountToLA triggered at: $(Get-Date)"

Import-Module Az.Accounts -Force -ErrorAction Stop
Import-Module Az.Monitor -Force -ErrorAction Stop
Import-Module Az.Storage -Force -ErrorAction Stop

# Configuration from environment variables (set these in local.settings.json or function app settings)
# Use Application Insights connection string available to Function Apps
$appInsightsConn = $env:APPLICATIONINSIGHTS_CONNECTION_STRING
if (-not $appInsightsConn) { $appInsightsConn = $env:APPINSIGHTS_CONNECTION_STRING }
$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
$ResourceGroupName = $env:STORAGE_RESOURCE_GROUP
$StorageAccountName = $env:STORAGE_ACCOUNT_NAME

if (-not $appInsightsConn) {
    Write-Error "Application Insights connection string must be set in APPLICATIONINSIGHTS_CONNECTION_STRING or APPINSIGHTS_CONNECTION_STRING"
    return
}

# parse connection string for instrumentation key and ingestion endpoint
$ikey = $null
$ingestionEndpoint = $null
if ($appInsightsConn -match 'InstrumentationKey=([^;]+)') { $ikey = $Matches[1] }
if ($appInsightsConn -match 'IngestionEndpoint=([^;]+)') { $ingestionEndpoint = $Matches[1].TrimEnd('/') }
if (-not $ingestionEndpoint) { $ingestionEndpoint = 'https://dc.services.visualstudio.com' }
if (-not $ikey) { Write-Warning "Instrumentation Key not present in connection string; telemetry envelopes will omit iKey." }

if (-not $SubscriptionId -or -not $ResourceGroupName -or -not $StorageAccountName) {
    Write-Error "Azure subscription, resource group, and storage account must be set in AZURE_SUBSCRIPTION_ID, STORAGE_RESOURCE_GROUP and STORAGE_ACCOUNT_NAME"
    return
}

Connect-AzAccount -Identity
Disable-AzContextAutosave -Scope Process | Out-Null
Set-AzContext -Subscription $SubscriptionId

# Get storage account resource id
$storage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
$storageResourceId = $storage.Id

# List queues using Az.Storage
$ctx = $storage.Context
$queues = Get-AzStorageQueue -Context $ctx -ErrorAction Stop

$now = Get-Date
$startTime = $now.AddMinutes(-5)

$records = @()

foreach ($q in $queues) {
    $queueName = $q.Name

    # Query metric: QueueMessageCount - take the latest value in the window
    $value = 0
    try {
        $metric = Get-AzMetric -ResourceId $storageResourceId -MetricName "QueueMessageCount" -TimeGrain 00:01:00 -StartTime $startTime -EndTime $now -Aggregation "Total" -ErrorAction Stop

        if ($metric -and $metric.TimeSeries) {
            # Find the timeseries that corresponds to this queue via its dimension values
            $ts = $metric.TimeSeries | Where-Object {
                $_.Metadatavalues -and ($_.Metadatavalues | Where-Object { $_.Name -in @('QueueName','EntityName') -and $_.Value -eq $queueName })
            } | Select-Object -First 1

            if ($ts -and $ts.Data) {
                # Pick last data point with a numeric total/average value
                $last = $ts.Data | Where-Object { $_.Total -ne $null -or $_.Average -ne $null } | Select-Object -Last 1
                if ($last) {
                    if ($null -ne $last.Total) { $value = [int]$last.Total }
                    elseif ($null -ne $last.Average) { $value = [int][math]::Round($last.Average) }
                }
            }
        }
    } catch {
        Write-Warning "Failed to get metric for queue $queueName : $_"
    }

    # Fallback: fetch approximate message count from storage if metric not found or zero
    if ($value -eq 0) {
        try {
            $qref = Get-AzStorageQueue -Name $queueName -Context $ctx -ErrorAction Stop
            if ($qref -and $qref.CloudQueue) {
                $qref.CloudQueue.FetchAttributes()
                $approx = $qref.CloudQueue.ApproximateMessageCount
                if ($null -ne $approx) { $value = [int]$approx }
            }
        } catch {
            Write-Warning "Fallback fetch attributes failed for queue ${queueName}: $_"
        }
    }

    $record = [PSCustomObject]@{
        TimeGenerated = (Get-Date).ToString("o")
        StorageAccount = $StorageAccountName
        QueueName = $queueName
        MessageCount = $value
    }
    $records += $record
}

if ($records.Count -eq 0) {
    Write-Host "No queue metrics to send."
    return
}

# Send telemetry (custom metric) to Application Insights using v2 ingestion endpoint
function Send-ToAppInsights {
    param(
        [Parameter(Mandatory=$true)] [string]$IngestionEndpoint,
        [Parameter(Mandatory=$false)] [string]$InstrumentationKey,
        [Parameter(Mandatory=$true)] [object[]]$Records
    )

    $endpoint = $IngestionEndpoint.TrimEnd('/') + '/v2/track'
    $envelopes = @()

    foreach ($r in $Records) {
        $metricValue = [double]$r.MessageCount
        $env = @{ 
            name = 'Microsoft.ApplicationInsights.Metric'
            time = $r.TimeGenerated
            iKey = $InstrumentationKey
            data = @{ 
                baseType = 'MetricData'
                baseData = @{ 
                    ver = 2
                    metrics = @( @{ name = 'QueueMessageCount'; value = $metricValue } )
                    properties = @{ 
                        StorageAccount = $r.StorageAccount
                        QueueName = $r.QueueName
                    }
                }
            }
        }
        $envelopes += $env
    }

    $bodyJson = $envelopes | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Method Post -Uri $endpoint -ContentType 'application/json' -Body $bodyJson -ErrorAction Stop
        Write-Host "Sent $($Records.Count) metric telemetry items to Application Insights at $endpoint"
    } catch {
        Write-Error "Failed to send to Application Insights: $_"
    }
}

Send-ToAppInsights -IngestionEndpoint $ingestionEndpoint -InstrumentationKey $ikey -Records $records

Write-Host "QueueMessageCountToLA completed at: $(Get-Date)"
