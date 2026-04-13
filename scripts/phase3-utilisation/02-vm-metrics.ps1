# VM Metrics — CPU % and Available Memory Bytes (30-day average/max)
# Auto-discovers all VMs across $allSubscriptions defined in config.ps1.

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

$results = foreach ($sub in $allSubscriptions) {
    az account set --subscription $sub | Out-Null
    $vms = az vm list --output json --only-show-errors | ConvertFrom-Json
    foreach ($vm in $vms) {
        foreach ($metric in @("Percentage CPU", "Available Memory Bytes")) {
            $raw = az monitor metrics list `
                --resource $vm.id --metric $metric `
                --start-time $start --end-time $end `
                --interval PT1H --aggregation Average Maximum --output json --only-show-errors | ConvertFrom-Json
            if ($raw -and $raw.value -and $raw.value[0].timeseries) {
                $data = $raw.value[0].timeseries[0].data | Where-Object { $_.average -ne $null }
                [PSCustomObject]@{
                    VM     = $vm.name
                    RG     = $vm.resourceGroup
                    Metric = $metric
                    Avg    = [math]::Round(($data | Measure-Object average -Average).Average, 1)
                    Max    = [math]::Round(($data | Measure-Object maximum -Maximum).Maximum, 1)
                }
            }
        }
    }
}

$results | Export-Csv "$outputDir\vm-metrics.csv" -NoTypeInformation
$results | Format-Table -AutoSize
