# Log Analytics — billable ingestion by table (last 30 days) across all workspaces
# Auto-discovers all Log Analytics workspaces via Resource Graph and queries each one.
# Output: single CSV with one row per DataType per workspace.

. "$PSScriptRoot\..\config.ps1"

$kqlQuery = "Usage | where TimeGenerated > ago(30d) | where IsBillable == true | summarize TotalGB = round(sum(Quantity) / 1024, 2) by DataType | order by TotalGB desc | take 20"

$wsGraphQuery = "resources | where type == 'microsoft.operationalinsights/workspaces' | project name, resourceGroup, subscriptionId, workspaceId = tostring(properties.customerId)"

Write-Host "Discovering Log Analytics workspaces..."
$wsResult = az graph query -q $wsGraphQuery --subscriptions $allSubscriptions --output json --only-show-errors | ConvertFrom-Json
$allWorkspaces = if ($wsResult.data) { @($wsResult.data) } else { @() }
# Exclude auto-created DefaultWorkspace-* — system workspaces with negligible ingestion
$workspaces = @($allWorkspaces | Where-Object { $_.name -notlike 'DefaultWorkspace-*' })
Write-Host "Found $($allWorkspaces.Count) workspaces total, querying $($workspaces.Count) named workspaces"

$results = foreach ($ws in $workspaces) {
    Write-Host "  Querying $($ws.name)..."
    $raw = az monitor log-analytics query -w $ws.workspaceId --analytics-query $kqlQuery --output json --only-show-errors | ConvertFrom-Json
    if ($raw) {
        foreach ($row in $raw) {
            [PSCustomObject]@{
                Workspace     = $ws.name
                ResourceGroup = $ws.resourceGroup
                SubscriptionId = $ws.subscriptionId
                DataType      = $row.DataType
                TotalGB       = $row.TotalGB
            }
        }
    } else {
        Write-Host "    No data or no access"
    }
}

$results | Export-Csv "$outputDir\log-analytics-ingestion.csv" -NoTypeInformation
$results | Format-Table -AutoSize
