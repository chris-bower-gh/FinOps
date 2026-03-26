# Data Factory — Pipeline run counts, failure rate, and last status (last 30 days)
# Configure $dataFactories in config.ps1 before running.
# Identifies: active vs idle factories, failing pipelines burning Managed VNET IR time.
#
# IMPORTANT: A high RunCount at high FailureRate is a cost issue, not just an ops issue.
# Each failed run on a Managed VNET IR still bills for the 60-minute minimum IR charge.
# Review FailureRate% column first — 100% failure = all IR time is waste.

. "$PSScriptRoot\..\config.ps1"

$lastRunTime = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
$now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

$results = foreach ($f in $dataFactories) {
    az account set --subscription $f.Sub | Out-Null
    $raw = az datafactory pipeline-run query-by-factory `
        --factory-name $f.Name `
        --resource-group $f.RG `
        --last-updated-after $lastRunTime `
        --last-updated-before $now `
        --output json 2>&1
    if ($raw -match '^\{') {
        $runs = ($raw | ConvertFrom-Json).value
        $runs | Group-Object pipelineName | ForEach-Object {
            $group       = $_.Group
            $total       = $group.Count
            $failed      = ($group | Where-Object { $_.status -eq 'Failed' }).Count
            $failRate    = if ($total -gt 0) { [math]::Round($failed / $total * 100, 1) } else { 0 }
            $lastRun     = $group | Sort-Object runEnd -Descending | Select-Object -First 1
            [PSCustomObject]@{
                Factory      = $f.Name
                Pipeline     = $_.Name
                RunCount     = $total
                FailedRuns   = $failed
                FailureRate  = "$failRate%"
                LastStatus   = $lastRun.status
                LastRunEnd   = $lastRun.runEnd
            }
        }
    } else {
        [PSCustomObject]@{
            Factory = $f.Name; Pipeline = "ERROR"; RunCount = 0
            FailedRuns = 0; FailureRate = "N/A"; LastStatus = ($raw | Out-String).Trim(); LastRunEnd = ""
        }
    }
}

$results | Sort-Object Factory, @{E='FailureRate'; Descending=$true}, Pipeline | Format-Table -AutoSize
$results | Export-Csv "$outputDir\data-factory-pipeline-runs.csv" -NoTypeInformation
