# Backup Vaults — retention periods per policy
# CONFIGURE: Set vaults array below
# Identifies excessively long retention periods driving storage costs

. "$PSScriptRoot\..\config.ps1"

$vaults = $backupVaults

$results = foreach ($v in $vaults) {
    az account set --subscription $v.sub | Out-Null
    $policies = az backup policy list `
        --vault-name $v.name `
        --resource-group $v.rg `
        --output json 2>$null | ConvertFrom-Json
    foreach ($p in $policies) {
        $retain = $p.properties.retentionPolicy
        [PSCustomObject]@{
            Vault           = $v.name
            Policy          = $p.name
            DailyRetainDays = $retain.dailySchedule.retentionDuration.count
            WeeklyRetainWks = $retain.weeklySchedule.retentionDuration.count
            MonthlyRetainMo = $retain.monthlySchedule.retentionDuration.count
            YearlyRetainYrs = $retain.yearlySchedule.retentionDuration.count
        }
    }
}

$results | Format-Table -AutoSize
