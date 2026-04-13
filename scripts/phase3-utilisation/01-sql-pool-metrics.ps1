# SQL Elastic Pool Metrics — DTU/vCore consumption % and storage % (30-day)
# Configure $sqlPools in config.ps1 before running.

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

$results = foreach ($p in $sqlPools) {
    az account set --subscription $p.Sub | Out-Null
    $metrics = if ($p.Type -eq "DTU") { "dtu_consumption_percent,storage_percent" } else { "cpu_percent,storage_percent" }
    foreach ($metric in $metrics.Split(",")) {
        $raw = az monitor metrics list `
            --resource "/subscriptions/$($p.Sub)/resourceGroups/$($p.RG)/providers/Microsoft.Sql/servers/$($p.Server)/elasticPools/$($p.Pool)" `
            --metric $metric --start-time $start --end-time $end `
            --interval PT1H --aggregation Average Maximum --output json --only-show-errors | ConvertFrom-Json
        if ($raw -and $raw.value) {
            $data = $raw.value[0].timeseries[0].data | Where-Object { $_.average -ne $null }
            [PSCustomObject]@{
                Pool   = $p.Pool
                Metric = $metric
                Avg    = [math]::Round(($data | Measure-Object average -Average).Average, 1)
                Max    = [math]::Round(($data | Measure-Object maximum -Maximum).Maximum, 1)
            }
        }
    }
}

$results | Export-Csv "$outputDir\sql-pool-metrics.csv" -NoTypeInformation
$results | Format-Table -AutoSize
