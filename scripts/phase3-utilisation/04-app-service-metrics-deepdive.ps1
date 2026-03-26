# App Service Plan Deep-Dive Metrics — 7-day 1-minute CPU and Memory
# Configure $appServicePlansDeepDive in config.ps1 before running.
#
# Run AFTER 04-app-service-metrics.ps1 has flagged a plan as a right-sizing candidate.
# IMPORTANT: Always pull BOTH CPU and memory before recommending any tier change.
#   - Memory is often the binding constraint. A plan low on CPU may be near its memory ceiling.
#   - Memory % is relative to the CURRENT SKU's allocation. Convert to GB to assess headroom
#     against the TARGET SKU's ceiling — not the current one.
#   - P0v3 is a burstable tier (0.25 vCPU baseline) — CPU % on P0v3 does not translate
#     directly to CPU % on B1 (1 full vCPU). The script notes this where Sku = P0v3.
#
# Output:
#   - Console: P95/P99/Peak %, peak memory in GB, headroom on current and candidate SKUs
#   - CSV:     Full 7-day 1-minute time series per plan per metric

. "$PSScriptRoot\..\config.ps1"

$end   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Memory ceilings in GB by SKU name — used to convert % to absolute GB
$memCeilings = @{
    'B1'  = 1.75; 'B2'  = 3.5;  'B3'  = 7.0
    'S1'  = 1.75; 'S2'  = 3.5;  'S3'  = 7.0
    'P0v3'= 4.0;  'P1v3'= 8.0;  'P2v3'= 16.0; 'P3v3' = 32.0
    'WS1' = 3.5;  'WS2' = 7.0;  'WS3' = 14.0
}

# Candidate SKU ceilings — used to show available headroom if plan is downgraded
$candidateCeilings = @{
    'B1' = 1.75; 'B2' = 3.5; 'B3' = 7.0
    'S1' = 1.75; 'S2' = 3.5; 'S3' = 7.0
    'P1v3' = 8.0; 'P2v3' = 16.0
}

foreach ($p in $appServicePlansDeepDive) {
    az account set --subscription $p.Sub | Out-Null
    $ceiling = if ($memCeilings[$p.Sku]) { $memCeilings[$p.Sku] } else { $null }

    Write-Host "`n====== $($p.Name) (current SKU: $($p.Sku)) ======"

    foreach ($metric in @("CpuPercentage", "MemoryPercentage")) {
        $raw = az monitor metrics list `
            --resource "/subscriptions/$($p.Sub)/resourceGroups/$($p.RG)/providers/Microsoft.Web/serverfarms/$($p.Name)" `
            --metric $metric --start-time $start --end-time $end `
            --interval PT1M --aggregation Maximum --output json 2>$null | ConvertFrom-Json

        if (-not ($raw -and $raw.value -and $raw.value[0].timeseries)) {
            Write-Warning "  No data for $metric"
            continue
        }

        $data = $raw.value[0].timeseries[0].data |
            Where-Object { $_.maximum -ne $null } |
            Select-Object @{N='Time'; E={$_.timeStamp}}, @{N='Value'; E={[math]::Round($_.maximum, 1)}}

        $data | Export-Csv "$outputDir\$($p.Name)-$metric-deepdive-7d.csv" -NoTypeInformation

        $sorted = $data | Select-Object -ExpandProperty Value | Sort-Object
        $n      = $sorted.Count
        $p95    = $sorted[[int]($n * 0.95)]
        $p99    = $sorted[[int]($n * 0.99)]
        $peak   = ($sorted | Measure-Object -Maximum).Maximum

        Write-Host "`n  $metric — P95: $p95%  |  P99: $p99%  |  Peak: $peak%"

        if ($metric -eq "MemoryPercentage" -and $ceiling) {
            $peakGB = [math]::Round($peak / 100 * $ceiling, 2)
            $p99GB  = [math]::Round($p99  / 100 * $ceiling, 2)
            Write-Host "  Memory (abs): Peak = $peakGB GB  |  P99 = $p99GB GB  (current ceiling: $ceiling GB)"

            # Show headroom against candidate SKUs
            if ($p.CandidateSku) {
                $candCeiling = if ($candidateCeilings[$p.CandidateSku]) { $candidateCeilings[$p.CandidateSku] } else { $null }
                if ($candCeiling) {
                    $headroom = [math]::Round($candCeiling - $peakGB, 2)
                    $status   = if ($headroom -gt 0) { "OK ($headroom GB headroom at peak)" } else { "INSUFFICIENT ($([math]::Abs($headroom)) GB over ceiling)" }
                    Write-Host "  Headroom on candidate $($p.CandidateSku) ($candCeiling GB ceiling): $status"
                }
            }
        }

        # Note P0v3 CPU interpretation
        if ($metric -eq "CpuPercentage" -and $p.Sku -eq "P0v3") {
            Write-Host "  NOTE: P0v3 is burstable (0.25 vCPU baseline). CPU% is relative to the burstable core."
            Write-Host "        On B1 (1 full vCPU), the same workload would show approximately $(($peak * 0.25).ToString("F1"))% at peak."
        }

        Write-Host "  CSV: $outputDir\$($p.Name)-$metric-deepdive-7d.csv"
    }
}
