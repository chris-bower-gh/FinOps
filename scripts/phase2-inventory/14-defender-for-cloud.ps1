# Defender for Cloud — enabled plans per subscription
# CONFIGURE: Set subscriptions array below
# Identifies Standard-tier plans that are billing; excludes deprecated and free plans
# Output: defender-plans.csv in current directory

. "$PSScriptRoot\..\config.ps1"

$subscriptions = $allSubscriptions

$results = foreach ($sub in $subscriptions) {
    az account set --subscription $sub | Out-Null
    $response = az security pricing list --output json 2>$null | ConvertFrom-Json
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

$results | Export-Csv "defender-plans.csv" -NoTypeInformation
$results | Format-Table -AutoSize
