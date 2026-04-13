# App Service Plan Metrics — CPU % and Memory % (30-day average/max)
# Configure $appServicePlans in config.ps1 before running.

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

$results = foreach ($p in $appServicePlans) {
    az account set --subscription $p.Sub | Out-Null
    foreach ($metric in @("CpuPercentage", "MemoryPercentage")) {
        $raw = az monitor metrics list `
            --resource "/subscriptions/$($p.Sub)/resourceGroups/$($p.RG)/providers/Microsoft.Web/serverfarms/$($p.Name)" `
            --metric $metric --start-time $start --end-time $end `
            --interval PT1H --aggregation Average Maximum --output json --only-show-errors | ConvertFrom-Json
        if ($raw -and $raw.value -and $raw.value[0].timeseries) {
            $data = $raw.value[0].timeseries[0].data | Where-Object { $_.average -ne $null }
            [PSCustomObject]@{
                Plan   = $p.Name
                Metric = $metric
                Avg    = [math]::Round(($data | Measure-Object average -Average).Average, 1)
                Max    = [math]::Round(($data | Measure-Object maximum -Maximum).Maximum, 1)
            }
        }
    }
}

$results | Export-Csv "$outputDir\app-service-metrics.csv" -NoTypeInformation
$results | Format-Table -AutoSize
