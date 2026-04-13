# Azure FinOps Discovery Process Guide

A repeatable process for performing Azure cost optimisation exercises for customers managed via CSP (indirect).

---

## Folder Structure

```
FinOps/
├── FinOps-Process-Guide.md       ← this file (engagement process, steps 1-16)
├── FinOps-Reference-Library.md   ← detailed cost saving reference by service
├── scripts/                      ← reusable scripts (customer-agnostic)
└── [customer-name]/              ← all output for a specific engagement
```

---

## Prerequisites

- Azure CLI installed
- Resource Graph extension installed (one-time):
  ```bash
  az extension add --name resource-graph --yes
  ```
- Logged in to the customer's tenant:
  ```bash
  az login
  az account list --output table   # verify correct tenant/subscriptions are visible
  ```

---

## Step 1 — Get Subscription IDs

From the Azure portal (or `az account list`), identify all in-scope subscriptions for the customer.
Note which ones are likely empty/inaccessible and exclude them if needed.

Save the subscription IDs — you'll reuse them in every subsequent script.

---

## Step 2 — Full Resource Inventory

Run the following PowerShell script to pull all resources across all subscriptions, with pagination.
Replace `$subs` with the customer's subscription IDs.

```powershell
$subs = "'sub-id-1','sub-id-2','sub-id-3'"   # comma-separated, single-quoted

$allResources = @()
$skip = 0

do {
    $result = az graph query -q "resources | where subscriptionId in ($subs) | project name, type, resourceGroup, subscriptionId, location, kind, sku, tags" --first 1000 --skip $skip --output json | ConvertFrom-Json
    $allResources += $result.data
    $skip += 1000
} while ($result.data.Count -eq 1000)

$outputDir = ".\[customer-folder]"   # relative to where you cloned/placed the FinOps repo

# Save full resource list
$allResources | ConvertTo-Json -Depth 10 | Out-File "$outputDir\all-resources.json" -Encoding utf8

# Save type summary
$allResources | Group-Object type | Select-Object Count, Name | Sort-Object Count -Descending | Format-Table -AutoSize | Out-File "$outputDir\resource-types.txt" -Encoding utf8

Write-Host "Done. Total resources found: $($allResources.Count)"
```

**Output:** `all-resources.json`, `resource-types.txt`

**What to look for in resource-types.txt:**
- App Service Plans (`microsoft.web/serverfarms`) — SKU and utilisation
- Web/Function Apps (`microsoft.web/sites`) — idle or over-provisioned
- SQL Databases + Elastic Pools — tier optimisation
- Managed Disks — check for unattached
- Azure Bastion — expensive per instance (~£136/month)
- Log Analytics Workspaces — consolidation opportunity
- Public IPs — check for unassociated
- Recovery Services Vaults — backup policy optimisation
- Storage Accounts — Defender transaction charges

---

## Step 3 — Cost Export Collection

**Do this before any resource-level analysis.** Cost exports steer the investigation — they tell you where money is being spent so you can prioritise effort rather than working through every resource type blindly.

### CSP billing API limitation

If the customer is managed via CSP (indirect), the Azure billing API is not accessible. Cost data must be obtained via portal CSV exports instead.

### How to export

In the Azure Cost Management portal, for each subscription:

1. Navigate to **Cost Management → Cost Analysis**
2. Set the view to **By Resource** (not By Service — that view omits resource detail)
3. Set date range to **last full calendar month**
4. Set granularity to **None** (accumulated total, not daily)
5. Export to CSV
6. Name each file descriptively: `costs-[subscription-name].csv`
7. Place all files in `[customer-folder]/cost-exports/`

> **Note:** The "By Service" export only shows monthly totals per service — it does not show per-resource detail and is not useful. Discard if accidentally exported.

### Analysing the exports

Cost CSV columns: `ResourceId`, `ResourceType`, `ResourceLocation`, `ResourceGroupName`, `ServiceName`, `Meter`, `Tags`, `CostUSD`, `Cost`, `Currency`

```powershell
# Summarise spend by ServiceName across all CSVs
$allCosts = Get-ChildItem "$outputDir\cost-exports\*.csv" | ForEach-Object {
    Import-Csv $_ | Where-Object { $_.Cost -ne '' -and $_.Cost -ne 'Cost' }
}

$allCosts | Group-Object ServiceName | ForEach-Object {
    [PSCustomObject]@{
        Service = $_.Name
        TotalCost = ($_.Group | ForEach-Object { [decimal]$_.Cost } | Measure-Object -Sum).Sum
    }
} | Sort-Object TotalCost -Descending | Format-Table -AutoSize
```

**What to look for:**

- Top 10 services by spend — these drive the investigation priority order
- Any services with high spend that haven't been considered (e.g. Service Bus, Microsoft Fabric, VPN Gateway)
- Cross-reference against resource inventory to confirm resource types exist
- Services with unexpectedly high spend relative to their resource count

---

## Step 4 — App Service Plan Analysis

### 4a — Get all App Service Plans

```powershell
$result = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.web/serverfarms' | project name, resourceGroup, subscriptionId, location, sku_name=sku.name, sku_tier=sku.tier, sku_capacity=sku.capacity, kind, tags" --first 1000 --output json | ConvertFrom-Json

$result.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\app-service-plans.json" -Encoding utf8
```

**What to look for:**

- Premium or Standard SKUs in Dev/Test/UAT environments (candidates for downgrade)
- `WorkflowStandard` (WS1) plans — Logic Apps Standard, check if actively used
- Capacity > 1 — manual scale-out, check if justified

**Important:** Separate plans per service may be intentional for VNet integration into different networks — do not recommend consolidation without confirming.

### 4b — Get all App Service Sites (apps per plan)

```powershell
$result = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.web/sites' | project name, kind, resourceGroup, subscriptionId, state=properties.state, serverFarmId=properties.serverFarmId, enabled=properties.enabled" --first 1000 --output json | ConvertFrom-Json

$result.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\app-service-sites.json" -Encoding utf8
```

**What to look for:**

- Plans with zero apps — pure waste, safe to delete
- Apps in `Stopped` state — investigate whether they can be deleted
- Cross-reference stopped apps with their plan SKU to assess impact

### 4c — Key findings pattern

After cross-referencing plans with sites:

- Flag any Premium/elevated SKU non-prod plans that have apps → need utilisation data before recommending downgrade
- Flag stopped apps on premium plans → candidate for deletion
- Note: stopped apps on a shared plan don't reduce plan cost unless all apps on that plan are removed

---

## Step 5 — App Service Utilisation Metrics

For any plans flagged in Step 4 as over-provisioned, pull 30-day CPU and memory metrics to support downgrade recommendations.

```powershell
# Example: pull CpuPercentage and MemoryPercentage for a specific App Service Plan
$subId    = "<subscription-id>"
$rg       = "<resource-group>"
$planName = "<plan-name>"
$end      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$start    = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

az monitor metrics list `
  --resource "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Web/serverFarms/$planName" `
  --metric "CpuPercentage" "MemoryPercentage" `
  --interval PT1H `
  --start-time $start `
  --end-time $end `
  --output json | Out-File "$outputDir\metrics-$planName.json" -Encoding utf8
```

Run this for each flagged plan. Key thresholds:

- **CPU avg < 20%, max < 50%** → strong case for downgrade
- **Memory avg < 40%, max < 70%** → strong case for downgrade

---

## Step 6 — SQL Analysis

### 6a — Get SQL databases, elastic pools and SQL VMs

```powershell
# Databases
$dbs = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.sql/servers/databases' | project name, resourceGroup, subscriptionId, location, sku_name=sku.name, sku_tier=sku.tier, sku_capacity=sku.capacity, kind, tags" --first 1000 --output json | ConvertFrom-Json
$dbs.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\sql-databases.json" -Encoding utf8

# Elastic pools
$pools = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.sql/servers/elasticpools' | project name, resourceGroup, subscriptionId, location, sku_name=sku.name, sku_tier=sku.tier, sku_capacity=sku.capacity, tags" --first 1000 --output json | ConvertFrom-Json
$pools.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\sql-elasticpools.json" -Encoding utf8

# SQL Virtual Machines
$sqlvms = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.sqlvirtualmachine/sqlvirtualmachines' | project name, resourceGroup, subscriptionId, location, sqlImageSku=properties.sqlImageSku, sqlServerLicenseType=properties.sqlServerLicenseType, tags" --first 1000 --output json | ConvertFrom-Json
$sqlvms.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\sql-vms.json" -Encoding utf8
```

**What to look for:**

- Elastic pools with high DTU/vCore capacity at low utilisation — pull metrics to confirm
- Pools tagged as serving multiple environments from one instance (e.g. "prod / staging") — 400+ DTU may be over-provisioned
- `GeneralPurpose` (vCore) pools — often more expensive than DTU equivalent; check CPU and storage utilisation
- SQL VMs running `Developer` edition — SQL license is free, cost is VM compute only
- Completely empty pools (0% DTU, 0% storage) — candidate for deletion

### 6b — Get SQL server names (needed for metrics)

```powershell
$result = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.sql/servers' | project name, resourceGroup, subscriptionId" --first 1000 --output json | ConvertFrom-Json
$result.data | Format-Table -AutoSize
```

### 6c — Pull elastic pool utilisation metrics

```powershell
$end   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$start = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# DTU-based pools: use dtu_consumption_percent
# vCore-based (GeneralPurpose) pools: use cpu_percent
# Also pull storage_percent for all

$resourceId = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Sql/servers/$serverName/elasticPools/$poolName"

az monitor metrics list `
  --resource $resourceId `
  --metric "dtu_consumption_percent" "storage_percent" `
  --interval PT1H `
  --start-time $start `
  --end-time $end `
  --output json
```

**Key thresholds:**

- DTU avg < 10%, max < 40% → strong case for downgrade
- Storage > 70% → verify storage limits before reducing vCores/DTUs
- 0% DTU and 0% storage → pool is empty, candidate for deletion
- Off-peak spikes → investigate automated jobs before recommending downgrade

---

## Step 7 — Compute: VMs and Managed Disks

### 7a — Get all VMs

```powershell
$vms = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.compute/virtualmachines' | project name, resourceGroup, subscriptionId, location, vmSize=properties.hardwareProfile.vmSize, osType=properties.storageProfile.osDisk.osType, powerState=properties.extended.instanceView.powerState.displayStatus, tags" --first 1000 --output json | ConvertFrom-Json
$vms.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\vms.json" -Encoding utf8
```

**What to look for:**

- VMs that are stopped but not deallocated — still incurring compute cost
- Non-production VMs with no auto-shutdown schedule
- Oversized VMs — pull CPU/memory metrics to confirm

### 7b — Get unattached managed disks

```powershell
$disks = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.compute/disks' | where properties.diskState == 'Unattached' | project name, resourceGroup, subscriptionId, diskSizeGB=properties.diskSizeGB, sku_name=sku.name, tags" --first 1000 --output json | ConvertFrom-Json
$disks.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\unattached-disks.json" -Encoding utf8
Write-Host "Unattached disks: $($disks.data.Count)"
```

Unattached disks are pure waste — no utilisation check needed, straight to deletion recommendation.

---

## Step 8 — Networking

### 8a — Unassociated public IPs

```powershell
$pips = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/publicipaddresses' | where isnull(properties.ipConfiguration) | project name, resourceGroup, subscriptionId, sku_name=sku.name, tags" --first 1000 --output json | ConvertFrom-Json
$pips.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\unassociated-pips.json" -Encoding utf8
Write-Host "Unassociated public IPs: $($pips.data.Count)"
```

### 8b — Azure Bastion instances

```powershell
$bastions = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/bastionhosts' | project name, resourceGroup, subscriptionId, sku_name=sku.name, tags" --first 1000 --output json | ConvertFrom-Json
$bastions.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\bastion.json" -Encoding utf8
```

**What to look for:**

- Basic SKU vs Standard SKU — Standard costs significantly more
- Multiple Bastion instances across subscriptions — consolidation may be possible
- Bastions in dev/test subscriptions — often unnecessary if developers use other access methods

### 8c — Azure Firewall

```powershell
$firewalls = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/azurefirewalls' | project name, resourceGroup, subscriptionId, sku_name=properties.sku.name, sku_tier=properties.sku.tier, tags" --first 1000 --output json | ConvertFrom-Json
$firewalls.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\firewalls.json" -Encoding utf8
```

**Note:** Check whether URL filtering / Web Categories feature is in use before recommending SKU downgrade — removing this feature can have security implications.

### 8d — Orphaned private endpoints

```powershell
$peps = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/privateendpoints' | project name, resourceGroup, subscriptionId, connectionState=properties.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status, tags" --first 1000 --output json | ConvertFrom-Json
$peps.data | Where-Object { $_.connectionState -ne 'Approved' } | ConvertTo-Json -Depth 5 | Out-File "$outputDir\orphaned-peps.json" -Encoding utf8
Write-Host "Non-approved private endpoints: $(($peps.data | Where-Object { $_.connectionState -ne 'Approved' }).Count)"
```

Private endpoints cost ~£5-6/month each. Most will be intentional — only flag those with non-Approved connection state as orphaned.

---

## Step 9 — Storage Accounts

```powershell
$storage = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.storage/storageaccounts' | project name, resourceGroup, subscriptionId, kind, sku_name=sku.name, sku_tier=sku.tier, accessTier=properties.accessTier, tags" --first 1000 --output json | ConvertFrom-Json
$storage.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\storage-accounts.json" -Encoding utf8
```

**What to look for:**

- Defender for Cloud — Storage accounts with high transaction volumes may be incurring excess Defender charges (same pattern as previous customers)
- Redundancy tier — GRS/GZRS where LRS/ZRS would suffice for non-critical data
- Access tier — Hot tier for infrequently accessed data

---

## Step 10 — Microsoft Defender for Cloud

```powershell
foreach ($sub in $subList) {
    az security pricing list --subscription $sub --output json
}
```

**What to look for:**

- Defender for Storage enabled on accounts with high transaction volumes → disable or configure per-storage account
- Defender plans enabled for resource types that don't exist in the subscription
- Blob malware scanning enabled on storage used only for ASR cache or FSLogix → unnecessary

---

## Step 11 — Log Analytics Workspaces

```powershell
$laws = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.operationalinsights/workspaces' | project name, resourceGroup, subscriptionId, retentionDays=properties.retentionInDays, sku=properties.sku.name, dailyCap=properties.workspaceCapping.dailyQuotaGb, tags" --first 1000 --output json | ConvertFrom-Json
$laws.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\log-analytics.json" -Encoding utf8
```

**What to look for:**

- Large number of workspaces — consolidation reduces per-GB ingestion cost through volume discounts
- No daily cap set (`dailyQuotaGb = -1`) — risk of runaway ingestion costs
- Retention > 30 days — additional cost for extended retention
- Workspaces with very low ingestion (check Azure Monitor ingestion metrics)

---

## Step 12 — Recovery Services Vaults (Backups)

```powershell
$vaults = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.recoveryservices/vaults' | project name, resourceGroup, subscriptionId, sku_name=sku.name, tags" --first 1000 --output json | ConvertFrom-Json
$vaults.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\recovery-vaults.json" -Encoding utf8
```

**What to look for:**

- Backup policies with excessive snapshot frequency (e.g. hourly snapshots where daily would suffice)
- Long retention periods for non-critical data
- FSLogix / ASR cache storage accounts being backed up unnecessarily

---

## Step 13 — Service Bus, API Management, Synapse, Fabric

```powershell
# Service Bus
$sb = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.servicebus/namespaces' | project name, resourceGroup, subscriptionId, sku_name=sku.name, sku_tier=sku.tier, tags" --first 1000 --output json | ConvertFrom-Json
$sb.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\servicebus.json" -Encoding utf8

# API Management
$apim = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.apimanagement/service' | project name, resourceGroup, subscriptionId, sku_name=sku.name, sku_capacity=sku.capacity, tags" --first 1000 --output json | ConvertFrom-Json
$apim.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\apim.json" -Encoding utf8

# Synapse
$synapse = az graph query -q "resources | where subscriptionId in ($subs) | where type in ('microsoft.synapse/workspaces', 'microsoft.synapse/workspaces/bigdatapools') | project name, type, resourceGroup, subscriptionId, tags" --first 1000 --output json | ConvertFrom-Json
$synapse.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\synapse.json" -Encoding utf8

# Fabric
$fabric = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.fabric/capacities' | project name, resourceGroup, subscriptionId, sku_name=sku.name, sku_tier=sku.tier, tags" --first 1000 --output json | ConvertFrom-Json
$fabric.data | ConvertTo-Json -Depth 5 | Out-File "$outputDir\fabric.json" -Encoding utf8
```

**What to look for:**

- Service Bus Premium tier (~£550/month per namespace) — check if Premium features are needed
- API Management Developer/Consumption vs Standard/Premium — large price difference
- Synapse Big Data Pools — check if paused when not in use; auto-pause settings
- Fabric Capacity — SKU tier (F2 vs F64 etc.), check if it can be paused outside business hours

---

## Step 14 — Azure Advisor Cost Recommendations

```powershell
foreach ($sub in $subList) {
    az advisor recommendation list --subscription $sub --category Cost --output json
}
```

Use as a cross-check against findings — Advisor often surfaces rightsizing and reserved instance opportunities.

---

## Step 15 — Pricing Lookup

Use the Azure Retail Prices API to get accurate current pricing for all SKUs identified. Do not use estimated figures in the final report.

```powershell
# Example: get price for a specific SKU in UK South
$sku = "P1 mv3"   # adjust per SKU naming in the API
$url = "https://prices.azure.com/api/retail/prices?`$filter=armRegionName eq 'uksouth' and skuName eq '$sku' and priceType eq 'Consumption'"
Invoke-RestMethod -Uri $url | Select-Object -ExpandProperty Items
```

Cross-reference each flagged resource against its current and proposed SKU price to calculate monthly saving.

---

## Step 16 — Report Production

Use `scripts/generate_report.py` as the starting point. Copy it into the customer folder, set `TEMPLATE_PATH` to any previous engagement `.docx`, set `OUTPUT_PATH`, and populate with findings. Run with `python generate_report.py`.

The report structure is:

1. Overview — scope and total spend
2. Findings by category (one H2 per category, H3 per sub-finding, evidence table, saving line)
3. Summary table: Finding | Monthly Saving | Effort | Risk
4. Pricing note: figures based on Azure Retail Prices API; actual savings may vary based on CSP discounting

See `FinOps-AI-Prompt.md` → *Generating the Word Report* for formatting rules and AI guidance.

---

> For detailed cost saving reference material by service, see **[FinOps-Reference-Library.md](FinOps-Reference-Library.md)**.

---
