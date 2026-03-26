# SQL Elastic Pool Deep-Dive Metrics — 7-day 1-minute granularity
# Configure $sqlPoolsDeepDive in config.ps1 before running.
#
# Run AFTER 01-sql-pool-metrics.ps1 has flagged a pool as a right-sizing candidate.
# 30-day hourly averages MASK short-duration spikes. A pool showing 6% average on hourly
# data can still hit 100% capacity every day for 5 minutes (a scheduled batch job).
# 1-minute data reveals burst patterns that determine safe right-sizing thresholds.
#
# Output:
#   - Console: P50/P95/P99/Max, business-hours P99, idle%, spike warnings
#   - CSV:     Full 7-day 1-minute time series for each pool (for manual review in Excel)

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($p in $sqlPoolsDeepDive) {
    az account set --subscription $p.Sub | Out-Null
    $metric = if ($p.Type -eq "DTU") { "dtu_consumption_percent" } else { "cpu_percent" }

    $raw = az monitor metrics list `
        --resource "/subscriptions/$($p.Sub)/resourceGroups/$($p.RG)/providers/Microsoft.Sql/servers/$($p.Server)/elasticPools/$($p.Pool)" `
        --metric $metric --start-time $start --end-time $end `
        --interval PT1M --aggregation Maximum --output json 2>$null | ConvertFrom-Json

    if (-not ($raw -and $raw.value -and $raw.value[0].timeseries)) {
        Write-Warning "No data returned for $($p.Pool)"
        continue
    }

    $data = $raw.value[0].timeseries[0].data |
        Where-Object { $_.maximum -ne $null } |
        Select-Object @{N='Time'; E={$_.timeStamp}}, @{N='Value'; E={[math]::Round($_.maximum, 1)}}

    # Export full time series for manual spike analysis (open in Excel to chart)
    $data | Export-Csv "$outputDir\$($p.Pool)-deepdive-7d.csv" -NoTypeInformation

    $sorted  = $data | Select-Object -ExpandProperty Value | Sort-Object
    $n       = $sorted.Count
    $p50     = $sorted[[int]($n * 0.50)]
    $p95     = $sorted[[int]($n * 0.95)]
    $p99     = $sorted[[int]($n * 0.99)]
    $maxVal  = ($sorted | Measure-Object -Maximum).Maximum
    $idle    = ($data | Where-Object { $_.Value -eq 0 }).Count
    $idlePct = [math]::Round($idle / $n * 100, 1)

    # Business-hours P99: 07:00–19:00 UTC, Monday–Friday
    $bhData = $data | Where-Object {
        $dt = [datetime]$_.Time
        $dt.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday) -and
        $dt.Hour -ge 7 -and $dt.Hour -lt 19
    } | Select-Object -ExpandProperty Value | Sort-Object
    $bhP99 = if ($bhData.Count -gt 0) { $bhData[[int]($bhData.Count * 0.99)] } else { 'N/A' }

    Write-Host "`n=== $($p.Pool) ($metric, 7-day 1-min, $n data points) ==="
    Write-Host "Idle (0%): $idlePct%  |  P50: $p50  |  P95: $p95  |  P99: $p99  |  Max: $maxVal"
    Write-Host "Business-hours P99 (07:00-19:00 UTC Mon-Fri): $bhP99"
    Write-Host "Time series CSV: $outputDir\$($p.Pool)-deepdive-7d.csv"

    # Flag recurring saturation events (≥95% capacity)
    $spikes = $data | Where-Object { $_.Value -ge 95 }
    if ($spikes.Count -gt 0) {
        Write-Warning "$($spikes.Count) 1-minute periods at >=95% capacity — review time series CSV for pattern"
        Write-Host "First 5 spike timestamps:"
        $spikes | Select-Object -First 5 | Format-Table -AutoSize
    } else {
        Write-Host "No saturation events (>=95%) detected."
    }
}
