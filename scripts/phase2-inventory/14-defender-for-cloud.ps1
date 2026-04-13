# Defender for Cloud — enabled plans per subscription
# Identifies Standard-tier plans that are billing; excludes deprecated and free plans
# Output: 14-defender-for-cloud.csv in movera/resource-data/

. "$PSScriptRoot\..\config.ps1"

$outputPath = Join-Path $resourceDataDir "14-defender-for-cloud.csv"

$subscriptions = $allSubscriptions

$results = foreach ($sub in $subscriptions) {
    az account set --subscription $sub | Out-Null
    $response = az security pricing list --output json --only-show-errors | ConvertFrom-Json
    $plans = if ($response.value) { $response.value } else { $response }
    foreach ($p in $plans) {
        if ($p.pricingTier -eq "Standard" -and -not $p.deprecated) {
            [PSCustomObject]@{
                Subscription = $sub
                Plan         = $p.name
                SubPlan      = $p.subPlan
            }
        }
    }
}

$results | Export-Csv $outputPath -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host "Saved to $outputPath"
