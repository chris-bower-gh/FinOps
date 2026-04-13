# Service Bus Metrics — IncomingMessages, OutgoingMessages, ActiveMessages (30-day total)
# Configure $serviceBusNamespaces in config.ps1 before running.
# Note: Premium namespaces with private endpoints may return zero from outside the VNET.

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

$results = foreach ($ns in $serviceBusNamespaces) {
    az account set --subscription $ns.Sub | Out-Null
    foreach ($metric in @("IncomingMessages", "OutgoingMessages", "ActiveMessages")) {
        try {
            $raw = az monitor metrics list `
                --resource "/subscriptions/$($ns.Sub)/resourceGroups/$($ns.RG)/providers/Microsoft.ServiceBus/namespaces/$($ns.Name)" `
                --metric $metric --start-time $start --end-time $end `
                --interval P1D --aggregation Total --output json --only-show-errors | ConvertFrom-Json
            $total = 0
            if ($raw -and $raw.value -and $raw.value.Count -gt 0 -and
                $raw.value[0].timeseries -and $raw.value[0].timeseries.Count -gt 0) {
                $total = ($raw.value[0].timeseries[0].data |
                    Where-Object { $_.total -ne $null } |
                    Measure-Object total -Sum).Sum
            }
            [PSCustomObject]@{ Namespace = $ns.Name; Tier = $ns.Tier; Metric = $metric; Total30d = [int]$total }
        } catch {
            [PSCustomObject]@{ Namespace = $ns.Name; Tier = $ns.Tier; Metric = $metric; Total30d = "ERROR" }
        }
    }
}

$results | Export-Csv "$outputDir\servicebus-metrics.csv" -NoTypeInformation
$results | Format-Table -AutoSize
