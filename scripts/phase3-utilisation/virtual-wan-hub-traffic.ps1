# Virtual WAN Hub — data processed (checks if hub is routing traffic)
# CONFIGURE: Set hub resource ID below
# Zero traffic = hub may be redundant (still costs ~£129/month for infrastructure)

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($hubResourceId in $vwanHubResourceIds) {
    az monitor metrics list `
        --resource $hubResourceId `
        --metric "VirtualHubDataProcessed" `
        --start-time $start --end-time $end `
        --interval PT1H --aggregation Total `
        --output json | ConvertFrom-Json | Select-Object -ExpandProperty value |
        ForEach-Object {
            $nonZero = $_.timeseries[0].data | Where-Object { $_.total -gt 0 }
            [PSCustomObject]@{
                Hub          = $hubResourceId.Split("/")[-1]
                DataPoints   = $_.timeseries[0].data.Count
                NonZeroHours = $nonZero.Count
                TotalBytes   = ($_.timeseries[0].data | Measure-Object total -Sum).Sum
            }
        } | Format-Table -AutoSize
}
