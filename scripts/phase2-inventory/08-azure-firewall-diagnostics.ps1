# Azure Firewall — diagnostic settings
# NOTE: Diagnostic settings are extension resources; Resource Graph does not reliably return them.
#       Use this CLI command instead.
# Output: 08-azure-firewall-diagnostics.csv in movera/resource-data/

. "$PSScriptRoot\..\config.ps1"

$outputPath = Join-Path $resourceDataDir "08-azure-firewall-diagnostics.csv"

$results = foreach ($id in $firewallResourceIds) {
    $firewallName = $id.Split('/')[-1]
    $raw = az monitor diagnostic-settings list --resource $id --output json 2>$null
    if ($raw) {
        $settings = $raw | ConvertFrom-Json
        if ($settings.Count -eq 0) {
            [PSCustomObject]@{
                FirewallName         = $firewallName
                SettingName          = "NONE"
                WorkspaceId          = ""
                StorageAccountId     = ""
                EnabledLogCategories = ""
            }
        } else {
            foreach ($s in $settings) {
                $enabledLogs = ($s.logs | Where-Object { $_.enabled } | ForEach-Object { $_.category }) -join "; "
                [PSCustomObject]@{
                    FirewallName         = $firewallName
                    SettingName          = $s.name
                    WorkspaceId          = $s.workspaceId
                    StorageAccountId     = $s.storageAccountId
                    EnabledLogCategories = $enabledLogs
                }
            }
        }
    }
}

$results | Export-Csv $outputPath -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host "Saved to $outputPath"
