# Backup Vaults — retention periods per policy
# Identifies excessively long retention periods driving storage costs
# Output: 16-backup-retention.csv in movera/resource-data/

. "$PSScriptRoot\..\config.ps1"

$outputPath = Join-Path $resourceDataDir "16-backup-retention.csv"

$vaults = $backupVaults

$results = foreach ($v in $vaults) {
    az account set --subscription $v.Sub | Out-Null
    $policies = az backup policy list `
        --vault-name $v.Name `
        --resource-group $v.RG `
        --output json --only-show-errors | ConvertFrom-Json
    foreach ($p in $policies) {
        $retain = $p.properties.retentionPolicy
        [PSCustomObject]@{
            Vault           = $v.Name
            Policy          = $p.name
            DailyRetainDays = $retain.dailySchedule.retentionDuration.count
            WeeklyRetainWks = $retain.weeklySchedule.retentionDuration.count
            MonthlyRetainMo = $retain.monthlySchedule.retentionDuration.count
            YearlyRetainYrs = $retain.yearlySchedule.retentionDuration.count
        }
    }
}

$results | Export-Csv $outputPath -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host "Saved to $outputPath"
