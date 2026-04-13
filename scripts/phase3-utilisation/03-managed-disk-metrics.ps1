# Managed Disk IOPS & Throughput Metrics — 30-day max/avg for Premium SSD tier assessment
# Collects metrics for all ATTACHED Premium SSD disks across $allSubscriptions.
# Unattached disks are pure waste — handled separately by 03-managed-disks.kql.
#
# Output includes Standard SSD limits for the provisioned size so the CSV can be
# used directly to determine tier-down viability without a separate lookup:
#   PeakCombinedIops   <= StdSSDIopsLimit       → IOPS safe to downgrade
#   PeakCombinedMBps   <= StdSSDThroughputMBpsLimit  → throughput safe to downgrade
#   FitsStdSSD = Yes/No/NoData
#
# NOTE: PeakCombined is the sum of MaxRead + MaxWrite — conservative (simultaneous peaks
# are unlikely) but correct for capacity planning. Standard SSD limits are combined totals.
#
# NOTE: AVD session host OS disks (resource groups containing 'avd') are excluded —
# they are 128 GB Premium_LRS and are not candidates for tier-down recommendations.
#
# Metric names: Microsoft.Compute/disks platform metrics (Azure Monitor)
# If a disk returns NoData, verify it has been active in the last 30 days.

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Standard SSD (Enn) IOPS and throughput limits by provisioned size
# Source: https://learn.microsoft.com/azure/virtual-machines/disks-types#standard-ssds
function Get-StdSsdLimits {
    param ([int]$SizeGB)
    if     ($SizeGB -le 32)    { return @{ Iops = 120;  ThroughputMBps = 25  } }
    elseif ($SizeGB -le 64)    { return @{ Iops = 240;  ThroughputMBps = 50  } }
    elseif ($SizeGB -le 512)   { return @{ Iops = 500;  ThroughputMBps = 100 } }
    elseif ($SizeGB -le 4096)  { return @{ Iops = 500;  ThroughputMBps = 60  } }
    elseif ($SizeGB -le 8192)  { return @{ Iops = 1300; ThroughputMBps = 400 } }
    elseif ($SizeGB -le 16384) { return @{ Iops = 2000; ThroughputMBps = 600 } }
    else                       { return @{ Iops = 4000; ThroughputMBps = 750 } }
}

$prodSubSet = [System.Collections.Generic.HashSet[string]]$prodSubscriptions

$graphQuery = "resources | where type == 'microsoft.compute/disks' | where sku.name startswith 'Premium' | where properties.diskState == 'Attached' | project id, name, resourceGroup, subscriptionId, skuName = tostring(sku.name), diskSizeGB = toint(properties.diskSizeGB), managedBy = tostring(properties.managedBy)"

Write-Host "Querying Resource Graph for Premium attached disks..."
$allDisks = [System.Collections.Generic.List[object]]::new()
$skip = 0
do {
    Write-Host "  Fetching page at skip=$skip..."
    $graphResult = az graph query -q $graphQuery --subscriptions $allSubscriptions --first 100 --skip $skip --output json --only-show-errors | ConvertFrom-Json
    $page = if ($graphResult.data) { @($graphResult.data) } else { @() }
    foreach ($item in $page) { $allDisks.Add($item) }
    $skip += 100
} while ($page.Count -eq 100)
Write-Host "Found $($allDisks.Count) Premium attached disks total"

# Exclude AVD session host OS disks — 128 GB Premium_LRS, not candidates for tier-down
$allDisks = @($allDisks | Where-Object { $_.resourceGroup -notmatch 'avd' })
Write-Host "After excluding AVD resource groups: $($allDisks.Count) disks to process"

$i = 0
$results = foreach ($disk in $allDisks) {
    $i++
    Write-Host "[$i/$($allDisks.Count)] $($disk.name)"
    $env = if ($prodSubSet.Contains($disk.subscriptionId)) { "Prod" } else { "NonProd" }
    $limits = Get-StdSsdLimits -SizeGB $disk.diskSizeGB

    $metricsMap = @{}
    foreach ($metric in @(
        "Composite Disk Read Operations/sec",
        "Composite Disk Write Operations/sec",
        "Composite Disk Read Bytes/sec",
        "Composite Disk Write Bytes/sec"
    )) {
        $raw = az monitor metrics list `
            --resource $disk.id --metric $metric `
            --start-time $start --end-time $end `
            --interval PT1H --aggregation Average Maximum --output json --only-show-errors | ConvertFrom-Json
        if ($raw -and $raw.value -and $raw.value[0].timeseries) {
            $data = $raw.value[0].timeseries[0].data | Where-Object { $_.average -ne $null }
            if ($data) {
                $metricsMap[$metric] = @{
                    Avg = [math]::Round(($data | Measure-Object average -Average).Average, 1)
                    Max = [math]::Round(($data | Measure-Object maximum -Maximum).Maximum, 1)
                }
            }
        }
    }

    $hasData = $metricsMap.Count -eq 4

    if ($hasData) {
        $maxReadIops  = $metricsMap["Composite Disk Read Operations/sec"].Max
        $maxWriteIops = $metricsMap["Composite Disk Write Operations/sec"].Max
        $maxReadMBps  = [math]::Round($metricsMap["Composite Disk Read Bytes/sec"].Max  / 1MB, 1)
        $maxWriteMBps = [math]::Round($metricsMap["Composite Disk Write Bytes/sec"].Max / 1MB, 1)
        $peakIops     = $maxReadIops + $maxWriteIops
        $peakMBps     = $maxReadMBps + $maxWriteMBps
        $fitsStdSSD   = if (($peakIops -le $limits.Iops) -and ($peakMBps -le $limits.ThroughputMBps)) { "Yes" } else { "No" }
    } else {
        $maxReadIops = $maxWriteIops = $maxReadMBps = $maxWriteMBps = $peakIops = $peakMBps = $null
        $fitsStdSSD  = "NoData"
    }

    [PSCustomObject]@{
        DiskName                  = $disk.name
        ResourceGroup             = $disk.resourceGroup
        SubscriptionId            = $disk.subscriptionId
        Environment               = $env
        SKU                       = $disk.skuName
        SizeGB                    = $disk.diskSizeGB
        AttachedTo                = $disk.managedBy -replace ".*/", ""
        AvgReadIops               = if ($hasData) { $metricsMap["Composite Disk Read Operations/sec"].Avg }  else { $null }
        MaxReadIops               = $maxReadIops
        AvgWriteIops              = if ($hasData) { $metricsMap["Composite Disk Write Operations/sec"].Avg } else { $null }
        MaxWriteIops              = $maxWriteIops
        PeakCombinedIops          = $peakIops
        AvgReadMBps               = if ($hasData) { [math]::Round($metricsMap["Composite Disk Read Bytes/sec"].Avg  / 1MB, 1) } else { $null }
        MaxReadMBps               = $maxReadMBps
        AvgWriteMBps              = if ($hasData) { [math]::Round($metricsMap["Composite Disk Write Bytes/sec"].Avg / 1MB, 1) } else { $null }
        MaxWriteMBps              = $maxWriteMBps
        PeakCombinedMBps          = $peakMBps
        StdSSDIopsLimit           = $limits.Iops
        StdSSDThroughputMBpsLimit = $limits.ThroughputMBps
        FitsStdSSD                = $fitsStdSSD
    }
}
$results | Export-Csv "$outputDir\disk-metrics.csv" -NoTypeInformation

$results | Format-Table -AutoSize
