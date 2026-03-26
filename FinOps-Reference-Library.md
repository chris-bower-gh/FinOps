# Azure Cost Optimisation Reference Library

A comprehensive, research-backed catalogue of cost saving opportunities by resource type. Use this alongside the [FinOps-Process-Guide.md](FinOps-Process-Guide.md) to inform discovery queries, know what to look for, and build targeted recommendations.

---

Sources: Microsoft Learn documentation, Azure Well-Architected Framework, official pricing pages (verified March 2026).

---

## APP SERVICE PLANS, WEB APPS & FUNCTION APPS

### App Service Plans — Tier Capabilities

Before recommending a downgrade, confirm which features the plan actually uses. The table below shows what each tier supports:

| Feature | Free/Shared | Basic (B1–B3) | Standard (S1–S3) | Premium V3 (P0v3–P3v3) |
| --- | --- | --- | --- | --- |
| Custom domains / SSL | No | Yes | Yes | Yes |
| VNet Integration | No | Yes | Yes | Yes |
| Deployment slots | No | No | Yes (up to 5) | Yes (up to 20) |
| Autoscale | No | No | Yes | Yes |
| Zone redundancy | No | No | No | Yes |

**Key point:** VNet integration is available on Basic tier. A plan on Premium or Standard "for VNet integration" can safely move to Basic. Deployment slots and autoscale are the genuine gates for Standard+. Always confirm whether slots or autoscale are in use before recommending a downgrade to Basic.

**P0v3 note:** P0v3 is a burstable tier with a 0.25 vCPU baseline. CPU% on P0v3 does not translate directly to B1 (1 full vCPU) — a spike to 100% on P0v3 equates to approximately 25% on B1. The deep-dive metrics script accounts for this automatically.

### App Service Plans — Tier Selection

| Finding | Detail |
| --- | --- |
| Premium V3 (Pxv3) with low utilisation | Often deployed "to be safe". CPU avg < 20% / memory avg < 40% = strong downgrade candidate. Check business hours metrics only. |
| B3 plans with low utilisation | B3 has 4 vCores / 7GB RAM. At < 20% CPU and < 40% memory (abs, not %) a B2 or B1 may suffice. Convert % to GB first — B3 memory is 7GB, so 40% = 2.8GB used; B1 has 1.75GB. |
| Standard (S-tier) plans | S-tier can no longer be selected for new plans (retired from portal). Existing S-tier plans can be downgraded to B-tier (no reserved capacity) or P-tier. |
| WorkflowStandard (WS1/WS2/WS3) | Logic Apps Standard hosting plan. WS1 (~£175/month) is fixed regardless of execution count. Low-volume Logic Apps workflows may cost less on Consumption model. |
| App Service Environments (ASE) | Minimum charge = 1 × I1v2 equivalent even with zero apps deployed. Very expensive. An empty ASE is pure waste. Also check: are ASEs being used where regular VNet-integrated plans would suffice? |
| Dev/Test subscriptions with production-tier plans | P1v3/P2v3 in dev/test — should these be B1/B2? Visual Studio subscribers can get significant discounts via Azure Dev/Test Pricing on non-Isolated tiers. |

### App Service Plans — Reservations

- **P3v3 reservations: up to 55% saving** vs pay-as-you-go with 3-year commitment; ~35% with 1-year
- Two types: Windows/platform-agnostic, and Linux-specific
- Reservation applies to matching instances in the subscription; not tied to specific plan resource
- **Important**: Reservations are a billing construct — you still pay even if you run fewer instances than reserved. Only commit to stable, long-running capacity.
- Isolated tier (ASE) also supports 1- and 3-year reservations on Iv2 SKUs

### App Service Plans — Hidden Costs

| Cost Driver | Notes |
|---|---|
| Plan persists after all apps deleted | A plan with no apps still charges at its full hourly rate. Always delete the plan (or scale to Free tier) after removing apps. |
| Storage accounts for backups/logs | Created alongside apps, persist after app deletion. Check for orphaned storage accounts created by App Service. |
| Key Vault for SSL certificates | App Service certificates require Key Vault. Check for Key Vault instances created solely for this purpose. |
| IP-based SSL bindings | First binding is free on Standard+. Additional bindings charged separately. |
| Deployment slots | Slots on Premium/Standard plans share the plan's compute. Multiple slots on the same plan don't cost more, but a dedicated slot plan (e.g. staging plan) does. |
| Log Analytics for diagnostic logs | If diagnostic settings send logs to a workspace, the ingestion charges sit in Log Analytics cost, not App Service cost. |
| Always On setting | On Basic+ tiers, keeps app warm. Not a direct cost but affects effective CPU baseline. |
| SCM site | The Kudu SCM endpoint always runs alongside the app on the same plan. Does not increase cost. |

### Function Apps

| Hosting Plan | Cost Model | When it's wasteful |
|---|---|---|
| Flex Consumption (recommended) | Per execution + memory, scales to zero | Rarely wasteful; check if "always ready instances" are configured unnecessarily |
| Premium (EP1/EP2/EP3) | Minimum 1 always-warm instance charged 24/7, even with 0 executions | Expensive if function runs rarely; consider Flex Consumption for VNet-integrated infrequent functions |
| Consumption (legacy) | Per execution, scales to zero, 1M free executions/month | Generally cheap; watch for high-volume functions where execution costs compound |
| Dedicated (App Service Plan) | Charged as App Service Plan | Wasteful if plan underutilised; fine if sharing with web apps |

- **Premium plan hidden cost**: minimum 1 always-warm instance charged even at zero load. If function runs < a few hours/day, Flex Consumption is likely cheaper.
- Premium plan VNet integration requires a dedicated plan subnet — separate from web apps.

### Logic Apps

| Type | Cost Model | Consideration |
|---|---|---|
| Consumption (multi-tenant) | Per action execution. Built-in actions have a free initial number; Managed connectors charged per call. | Very cheap at low volumes. Enterprise connectors (SAP, MQ) cost more per call. |
| Standard WS1 | ~£175/month fixed (1 vCPU, 3.5GB RAM). Unlimited built-in actions free. Managed connectors charged per call. | Break-even vs Consumption is ~50,000+ action executions/month. Not cost-effective for infrequent workflows. |
| Standard WS2/WS3 | 2× and 4× the WS1 rate respectively | Only justified at high action volumes |

- Standard tier needed for: VNet integration, single-tenant isolation, stateful sessions requiring private networking
- Standard tier is a flat monthly cost regardless of whether workflows run — check if workflows are actually active

### Detection Queries

```powershell
# Find empty App Service Plans (plans with no sites)
$plans = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.web/serverfarms' | project planId=tolower(id), name, resourceGroup, subscriptionId, sku_name=sku.name, sku_tier=sku.tier" --first 1000 --output json | ConvertFrom-Json
$sites = az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.web/sites' | project planId=tolower(tostring(properties.serverFarmId))" --first 1000 --output json | ConvertFrom-Json
$planIds = $sites.data | Select-Object -ExpandProperty planId | Sort-Object -Unique
$plans.data | Where-Object { $planIds -notcontains $_.planId }
```

```powershell
# Find stopped apps (state = Stopped)
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.web/sites' | where properties.state == 'Stopped' | project name, resourceGroup, subscriptionId, kind, planId=properties.serverFarmId" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

---

## AZURE SQL

### Elastic Pools — Rightsizing

| Finding | Detail |
| --- | --- |
| Standard DTU pools at low utilisation | avg DTU% < 10%, max < 40% → candidate to reduce DTU size. Minimum Standard tier sizes: 50, 100, 200, 400, 800, 1200, 1600 eDTU. |
| GeneralPurpose vCore pools at low utilisation | avg CPU% < 10%, max < 40% → reduce vCores. GP pools: 2, 4, 6, 8, 10, 12... vCores. GP 4 vCores ≈ Standard 400 DTU in cost. |
| Test/dev pools at 100 DTU with < 5% avg usage | Strong candidate for Basic tier (50 eDTU minimum) or deletion if unused. |
| Pools with zero utilisation and zero storage | Pool is empty — either delete or confirm workload is genuinely gone. |
| Off-peak spikes | **Always pull 7-day 1-minute metrics before recommending a downgrade.** 30-day hourly averages mask short-duration spikes. A pool showing 6% average can hit 100% capacity every day for a scheduled batch job. |

### Elastic Pools — Standard to Basic Downgrade Prerequisites

The Basic tier is significantly cheaper than Standard but has hard constraints that must be verified before recommending the change. Failure to check these will result in application errors after the downgrade.

| Prerequisite | Constraint | How to check |
| --- | --- | --- |
| Per-database storage | Maximum 2 GB used data per database | Query `sys.database_files` in each database: `SELECT SUM(size * 8.0 / 1024) AS UsedMB FROM sys.database_files` |
| Columnstore indexes | Not supported in Basic tier | `SELECT * FROM sys.indexes WHERE type = 5 OR type = 6` in each database |
| In-Memory OLTP | Not supported in Basic tier | `SELECT * FROM sys.filegroups WHERE type = 'FX'` in each database |
| Per-database eDTU cap | Hard cap of 5 eDTU per database regardless of pool size | Confirm with app team — any workload requiring burst above 5 eDTU will throttle |

The downgrade is fully reversible — upgrading back to Standard causes a brief connection interruption (typically under 30 seconds) with no data loss. Document the per-database eDTU cap caveat in the report so the team activating each environment can confirm before proceeding.

### SQL Databases — Individual Databases

| Finding | Detail |
|---|---|
| Serverless tier for intermittent databases | Single databases in GeneralPurpose vCore can use Serverless tier with auto-pause. Only storage charged when paused. Min auto-pause delay: 15 minutes. **Not supported**: geo-replication, LTR, Business Critical tier. **Note**: Azure Hybrid Benefit and Reserved Instances do NOT apply to serverless. |
| Dev/test databases that are always on | Convert to serverless with auto-pause, or stop/deallocate when not needed. |
| Databases with predictable steady load | Consider Reserved Capacity (1-year or 3-year) for up to 33% (1yr) or 56% (3yr) saving on provisioned compute. |
| Azure Hybrid Benefit | Apply existing SQL Server licence to Azure SQL. Up to 40% saving (Standard licence) or 55% (Enterprise licence). Check if AHB is applied to all eligible databases/pools. |
| Free tier | Exists for single databases: 32GB storage, 100K vCore seconds/month free. Only useful for very small development databases. |

### SQL Virtual Machines

| Finding | Detail |
|---|---|
| Developer edition | SQL licence is free — cost is VM compute only. No optimisation needed for licence. |
| Enterprise/Standard edition VMs | Azure Hybrid Benefit for SQL Server: up to 55% saving for Enterprise, 40% for Standard. Always check if AHB is applied. |
| VMs always on in non-production | Auto-shutdown schedules, or convert to use Azure SQL Database/Elastic Pool instead of IaaS. |
| Oversized VMs for SQL workloads | Memory-optimised VMs (Ev5, Edv5) may be cheaper per GB RAM than general purpose for SQL. Pull CPU and memory metrics. |

### Detection Queries

```powershell
# Check if Azure Hybrid Benefit is applied to SQL VMs
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.sqlvirtualmachine/sqlvirtualmachines' | project name, resourceGroup, subscriptionId, sqlImageSku=properties.sqlImageSku, sqlServerLicenseType=properties.sqlServerLicenseType" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data

# Check Azure Hybrid Benefit on SQL Elastic Pools
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.sql/servers/elasticpools' | project name, resourceGroup, subscriptionId, sku_name=sku.name, sku_tier=sku.tier, licenseType=properties.licenseType" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

---

## SERVICE BUS

### Premium vs Standard Tier

| Feature | Premium | Standard |
|---|---|---|
| Pricing | Fixed per messaging unit (~£550-600/month per MU) | Pay-per-operation (variable) |
| Private endpoints / VNet | ✅ Required for private endpoint | ❌ Not available |
| Message size | Up to 100MB | Up to 256KB |
| JMS 2.0 | ✅ | ❌ (JMS 1.1 subset only) |
| Performance | Predictable, dedicated resources | Variable latency |
| Partitioning | At namespace level | At entity level |
| Geo-replication (data) | ✅ | ❌ |

**Key question**: Does the customer need private endpoints for Service Bus? If yes → Premium required. If no → Standard may be sufficient and significantly cheaper.

**Rightsizing Premium MUs:**
- Start with 1 MU per namespace; scale up if CPU > 70%
- CPU < 20% → candidate to scale down MUs
- MUs can be dynamically adjusted without downtime
- Check Resource Usage metrics (CPU%) in Azure Monitor for each namespace

**Orphaned/idle namespaces:**
- Check for namespaces with no queues/topics, or queues with no active producers/consumers
- Check message count metrics — zero messages in/out over 30 days = candidate for deletion
- Auto-delete idle queue setting: queues can be configured to auto-delete after idle period

```powershell
# List all Service Bus namespaces with SKU and tier
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.servicebus/namespaces' | project name, resourceGroup, subscriptionId, location, sku_name=sku.name, sku_tier=sku.tier, sku_capacity=sku.capacity, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

---

## MICROSOFT FABRIC

### Capacity Management

| Finding | Detail |
|---|---|
| No pause/resume schedule | Fabric capacity runs 24/7 by default. If only used during business hours, a schedule can save ~60-70% of capacity cost. |
| Manual pause only | Pause is available via Portal or API. Automation via Azure Runbook (search "Fabric" in runbook gallery). |
| P SKU vs F SKU | **P SKUs (Power BI Premium)** cannot be paused. Only **F SKUs** support pause/resume. If on P SKU, this optimisation is not available. |
| Over-provisioned SKU | Check capacity utilisation in Microsoft Fabric Capacity Metrics app. Low utilisation consistently → downgrade to smaller F SKU. |
| Overages when paused | When pausing, cumulative overages are billed — confirm capacity is not being throttled before pausing. |

```powershell
# Find Fabric capacities and their SKU
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.fabric/capacities' | project name, resourceGroup, subscriptionId, sku_name=sku.name, sku_tier=sku.tier, state=properties.state, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

**Pause/resume API:**
```powershell
# Suspend (pause) a Fabric capacity
$token = (az account get-access-token --resource https://management.azure.com/ | ConvertFrom-Json).accessToken
Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Fabric/capacities/$capacityName/suspend?api-version=2023-11-01" -Method POST -Headers @{Authorization="Bearer $token"}

# Resume a Fabric capacity
Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Fabric/capacities/$capacityName/resume?api-version=2023-11-01" -Method POST -Headers @{Authorization="Bearer $token"}
```

---

## LOG ANALYTICS WORKSPACES

### Pricing Tiers

| Tier | When to use | Saving |
|---|---|---|
| Pay-as-you-go | < ~100GB/day per workspace | Baseline |
| Commitment 100GB/day | ≥ 100GB/day ingestion | Up to 15% saving |
| Commitment 200GB/day | ≥ 200GB/day | Up to 20% |
| Commitment 500GB/day+ | Large environments | Up to 30% |
| Dedicated Cluster | Multiple workspaces, combined ≥ 500GB/day | Aggregated discounts |

- **Check current ingestion**: Portal → Workspace → Usage and Estimated Costs → shows estimated cost at each commitment tier
- **31-day commitment period** — cannot drop to lower tier for 31 days after selecting one
- **Basic Logs tier (per table)**: lower ingestion cost, charges per query. Best for: infrequently queried tables (AKS container logs, debug tables, high-volume low-value tables). Not suitable for tables used in alerts.
- **Auxiliary Logs tier**: even lower ingestion cost than Basic. Best for long-term compliance data.

### Duplicate Ingestion (Common and Costly)

| Scenario | Fix |
|---|---|
| Log Analytics agent AND Azure Monitor agent on same VM | Run only one agent. Migrating from MMA to AMA — disable MMA immediately after AMA is configured, do not run both. |
| Multiple diagnostic settings sending same resource logs to same workspace | Check each resource — only one diagnostic setting per workspace per resource needed. |
| Same Prometheus metrics collected by both Managed Prometheus and Container Insights | Disable Container Insights metric collection if using Managed Prometheus (redundant). |
| Application Insights sending to workspace AND classic resource | Only workspace-based Application Insights benefits from commitment tiers; classic does not. Migrate classic to workspace-based. |

### Microsoft Sentinel on Workspace

**Critical**: When Sentinel is enabled on a workspace, ALL data in that workspace is subject to Sentinel pricing, not just security logs. This can double the effective cost of operational logs sent to a security workspace. Keep security and operational data in separate workspaces unless combined volume earns a commitment tier discount that offsets the Sentinel uplift.

### Application Insights

| Finding | Detail |
|---|---|
| Classic (non-workspace-based) | Cannot use commitment tiers or Basic Logs. Migrate to workspace-based to enable cost optimisation. |
| Sampling not configured | Sampling is the primary cost control tool. For high-volume apps, adaptive sampling or fixed-rate sampling should be configured. |
| Dependency tracking / Ajax calls | Disable if not actively analysed. |
| Performance counters | Disable modules not needed (dependency data collection if map feature unused). |
| Data cap not set | Set a daily cap to prevent runaway ingestion from badly behaved apps. |

### KQL: Find Top Tables by Ingestion Cost

```kql
// Run in Log Analytics workspace
Usage
| where TimeGenerated > ago(30d)
| summarize TotalGB = sum(Quantity) / 1000 by DataType
| sort by TotalGB desc
| take 20
```

```kql
// Find which VMs are generating most data
Heartbeat
| summarize count() by Computer, SourceComputerId
| join kind=leftouter (
    Usage | where TimeGenerated > ago(30d)
    | summarize DataGB = sum(Quantity) / 1000 by Computer
) on Computer
| sort by DataGB desc
```

---

## VIRTUAL MACHINES

### Rightsizing

| Finding | Detail |
|---|---|
| CPU avg < 5%, max < 20% over 30 days | Strongly oversized. Downsize VM SKU or consider B-series burstable for non-constant workloads. |
| CPU avg < 20%, max < 40% | Likely oversized. Gather more context (is there a known peak event not captured in 30 days?) |
| Memory avg < 30% | May be oversized on memory. Consider memory-optimised → general purpose swap. |
| Stopped but not deallocated | VM is stopped but still incurring compute charges. Deallocate (not just stop) or delete. |
| No auto-shutdown in non-production | Dev/test VMs should have auto-shutdown schedules (6pm weekdays, all weekend). |

### Azure Hybrid Benefit (AHB)

- **Windows Server**: Apply existing Windows Server licence with Software Assurance. Saves the Windows licence charge (~20-40% of VM cost depending on size).
- **SQL Server on VM**: Apply SQL Server licence (Standard = ~40% saving, Enterprise = ~55% saving).
- **RHEL/SUSE**: AHB available for Red Hat and SUSE Linux (if customer has existing licences).
- **How to check**: `az vm show --resource-group $rg --name $vmName --query "licenseType"` — should be "Windows_Server" or "Windows_Client" if AHB is applied.

```powershell
# Find VMs not using Azure Hybrid Benefit
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.compute/virtualmachines' | where properties.storageProfile.osDisk.osType == 'Windows' | where isempty(properties.licenseType) or properties.licenseType != 'Windows_Server' | project name, resourceGroup, subscriptionId, vmSize=properties.hardwareProfile.vmSize, licenseType=properties.licenseType" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

### Reserved Instances & Savings Plans

| Commitment | Saving vs PAYG | Applies to |
|---|---|---|
| 1-year Reserved Instance | ~30-35% | Specific VM size + region (exchangeable) |
| 3-year Reserved Instance | ~55-60% | Specific VM size + region |
| 1-year Savings Plan (compute) | ~15-17% | Any VM size, any region, any OS |
| 3-year Savings Plan (compute) | ~20-24% | Any VM size, any region, any OS |

- Reserved Instances = higher saving but locked to size/region; use for stable, long-running VMs
- Savings Plans = lower saving but flexible; use for variable fleet or when unsure of future sizing
- Check Advisor recommendations for RI candidates (Azure identifies VMs with 7-day+ continuous runtime)

### B-Series Burstable VMs

For VMs with low average CPU but occasional spikes (e.g. background processing, dev boxes):
- B-series accumulates CPU credits during low usage, spends them during bursts
- Significantly cheaper than equivalent D-series at low average utilisation
- **Risk**: if app genuinely needs sustained CPU above the baseline, B-series performs poorly

### Spot Instances

- Up to 90% discount vs pay-as-you-go, but can be evicted with 30-second notice
- Only appropriate for: batch processing, stateless workloads, non-production environments where restarts are acceptable

---

## MANAGED DISKS

### Unattached Disks

```powershell
# Find all unattached managed disks
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.compute/disks' | where properties.diskState == 'Unattached' | project name, resourceGroup, subscriptionId, diskSizeGB=properties.diskSizeGB, sku_name=sku.name, timeCreated=properties.timeCreated, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

Pure waste — no utilisation check needed. Charge is based on provisioned size, not used size.

| Disk SKU | Monthly cost per 1TB |
|---|---|
| Premium SSD P70 (1TB) | ~£130/month |
| Standard SSD E70 (1TB) | ~£60/month |
| Standard HDD S70 (1TB) | ~£30/month |

### Disk Rightsizing

- **Premium SSD → Standard SSD**: For non-critical data, development disks, or backups. Significant saving.
- **Provisioned size vs used size**: Disk cost is based on provisioned tier, not used space. A 1TB disk with 10GB used still costs the same as a full 1TB disk.
- **Disk snapshots**: Charged per GB. Old snapshots from deleted VMs are pure waste.

```powershell
# Find orphaned disk snapshots (associated VM no longer exists)
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.compute/snapshots' | project name, resourceGroup, subscriptionId, diskSizeGB=properties.diskSizeGB, timeCreated=properties.timeCreated, sourceResourceId=properties.creationData.sourceResourceId" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

---

## NETWORKING

### Azure Bastion

| SKU | Cost | Use Case |
|---|---|---|
| Developer | **Free** | Shared infrastructure, dev/test only, 1 VM at a time, limited regions |
| Basic | Hourly + data transfer | Production, fixed capacity, moderate connections |
| Standard | Higher hourly + data transfer | Production, scalable instances, native client, file transfer |
| Premium | Highest | Session recording, private-only deployment |

- Billing starts from deployment regardless of usage
- If Bastion is deployed in dev/test subscriptions: replace with Developer SKU (free) or remove if developers use VPN/ExpressRoute
- Multiple Bastions across VNets: if VNets are peered, a single Standard Bastion can serve all peered VNets

```powershell
# Find all Bastion instances and their SKU
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/bastionhosts' | project name, resourceGroup, subscriptionId, sku_name=sku.name, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

### Azure Firewall

| Tier | Cost | Key Difference |
|---|---|---|
| Basic | Cheapest | No IDPS, limited features |
| Standard | Mid | Full L7 filtering, threat intel |
| Premium | Most expensive | IDPS, URL categories, TLS inspection |

- **Premium → Standard downgrade**: Only if TLS inspection and IDPS are NOT in use. Check Firewall Policy for active IDPS/TLS settings before recommending.
- Azure Firewall charged hourly + per GB processed — check data processing volumes.
- Azure Firewall Manager: adds management overhead charge if used.

### Azure DDoS Protection

| Plan | Monthly Cost | When Needed |
|---|---|---|
| Basic (free) | **£0** | Included for all Azure services — protects against common L3/L4 attacks |
| IP Protection | Per protected public IP | Specific IPs needing enhanced protection |
| Network Protection | ~£2,500+/month flat + overages | VNets with critical public-facing services |

**Critical**: DDoS Network Protection Plan is ~£2,500+/month regardless of usage. If enabled and the workload does not genuinely require it, this is significant waste. Basic protection (free) handles most common DDoS scenarios.

```powershell
# Find DDoS protection plans
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/ddosprotectionplans' | project name, resourceGroup, subscriptionId, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

### Private Endpoints

- Each private endpoint: ~£5.50/month + data inbound/outbound processing charges
- 329 private endpoints (as seen in Cormar's inventory) = ~£1,800/month just in fixed charges
- Most will be intentional — only flag those with non-Approved connection state as orphaned

```powershell
# Find non-Approved private endpoints
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/privateendpoints' | project name, resourceGroup, subscriptionId, connectionState=properties.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data | Where-Object { $_.connectionState -ne 'Approved' }
```

### Public IP Addresses

```powershell
# Find unassociated (orphaned) public IPs
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/publicipaddresses' | where isnull(properties.ipConfiguration) | project name, resourceGroup, subscriptionId, sku_name=sku.name, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

Static Public IPs: ~£3/month each. Standard SKU static IPs charged even when not associated.

### NAT Gateway

- Charged hourly even with no active traffic processing
- Per-GB data processing charge on top
- Multiple subnets can share one NAT Gateway (cost effective)
- If a subnet has no outbound internet requirements, detaching the NAT Gateway saves the idle hourly charge

### Load Balancers

```powershell
# Find Load Balancers with empty backend pools
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/loadbalancers' | where array_length(properties.backendAddressPools) == 0 or isnull(properties.backendAddressPools) | project name, resourceGroup, subscriptionId, sku_name=sku.name" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

Standard SKU Load Balancers: charged hourly + per rule + per GB. Basic SKU is free but being retired.

### Application Gateway

```powershell
# Find Application Gateways (check for empty backend pools in portal)
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/applicationgateways' | project name, resourceGroup, subscriptionId, sku_name=properties.sku.name, sku_tier=properties.sku.tier, sku_capacity=properties.sku.capacity, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

- v1 SKU is retired — migration to v2 required (v2 is autoscaling, different pricing)
- WAF v2 is charged per gateway-hour + per CU (capacity unit) — check if WAF rules are actually configured
- Autoscale min instances: setting min = 0 saves cost during zero-traffic periods but introduces cold start

### VPN Gateways

```powershell
# Find VPN Gateways
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.network/virtualnetworkgateways' | project name, resourceGroup, subscriptionId, gatewayType=properties.gatewayType, sku_name=properties.sku.name, sku_tier=properties.sku.tier" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

- Charged hourly regardless of active connections
- Basic SKU VPN Gateways: being retired — migration to VpnGw1 or higher required
- If used only for dev/test site-to-site and can tolerate P2S, consider consolidation

### Virtual WAN

- Hub charges: ~£190/month per hub (Standard), regardless of traffic
- Routing infrastructure unit: additional charge per unit
- Check if Virtual WAN hubs are actively routing traffic or if standard VNet peering would suffice

---

## STORAGE ACCOUNTS

### Access Tiers

| Tier | Storage Cost | Access Cost | Use For |
|---|---|---|---|
| Hot | Higher | Lower | Frequently accessed data (daily) |
| Cool | Lower | Higher | Infrequently accessed (30+ days) |
| Cold | Even lower | Higher | Rarely accessed (90+ days) |
| Archive | Lowest | Highest + rehydration delay | Long-term retention (180+ days), compliance |

- **Lifecycle management policies** automate tier transitions: e.g. move to Cool after 30 days last modified, Archive after 180 days, delete after 365 days. **Free to configure.**
- **Important for Archive**: Rehydration (Archive → Hot/Cool) takes hours and is charged per GB. Only use Archive for data you can tolerate waiting for.

### Redundancy Tiers

| Redundancy | Monthly Cost Multiplier | Use For |
|---|---|---|
| LRS (locally redundant) | 1× | Non-critical data, dev/test, data already replicated elsewhere |
| ZRS (zone redundant) | ~1.25× | Production data in single region, resilience to zone failures |
| GRS (geo-redundant) | ~2× LRS | Data requiring geographic DR |
| GZRS | ~2.5× LRS | Highest redundancy — rarely necessary |

- **GRS → LRS downgrade**: significant saving for storage accounts used for backups/logs/temp data that don't require geo-redundancy. Confirm DR requirements first.

### Defender for Storage

- **Classic plan (per-transaction)**: charged per million transactions. **Very expensive** for high-volume accounts (ASR cache, FSLogix, backup storage, diagnostics). Common source of surprise bills.
- **New plan (per-storage-account)**: predictable per-account pricing with optional malware scanning add-on.
- **Malware scanning**: per-GB charged. Default cap 10,000GB/month. Can be disabled per-account.
- **Recommendation**: Migrate all accounts from Classic to new plan. Evaluate which accounts genuinely need malware scanning (e.g. user upload endpoints) vs which don't (backup/log/temp accounts).

```powershell
# Check Defender for Storage plans per subscription
foreach ($sub in $subList) {
    Write-Host "=== $sub ==="
    az security pricing show --name StorageAccounts --subscription $sub --output json | ConvertFrom-Json | Select-Object pricingTier, subPlan, freeTrialRemainingTime
}
```

### Other Storage Cost Items

- **Soft delete**: does not cost extra but delays actual capacity reduction. If 365-day soft delete is set and large volumes are being deleted, effective storage cost is high for a long time.
- **Blob versioning**: keeps previous versions. Every write creates a version. Can massively inflate storage costs for frequently overwritten blobs (e.g. logs, telemetry files).
- **Blob snapshots**: manual snapshots can accumulate if not cleaned up.

---

## MICROSOFT DEFENDER FOR CLOUD

### Plan Overview and Cost Guidance

| Plan | Per-unit cost | Commonly unnecessary |
|---|---|---|
| Defender for Servers Plan 1 | Per server/month | No — Plan 1 is the cheaper option if Plan 2 not needed |
| Defender for Servers Plan 2 | Per server/month (higher) | Use Plan 2 only if: file integrity monitoring, OS vulnerability assessment, or 500MB/day LA free data allocation needed |
| Defender for Storage | Per storage account + malware scanning | Classic plan very expensive for high-volume accounts |
| Defender for Databases | Per SQL server/month | Check if all databases on server are in scope |
| Defender for App Service | Per App Service Plan/month | Consider if required — not always necessary |
| Defender for Key Vault | Per 10K transactions | Can be expensive for high-transaction key vaults |
| Defender for Resource Manager | Flat per subscription | Lowest cost, but assess if needed |
| Defender for DNS | Flat per subscription | Can be disabled if using custom DNS resolvers |
| Defender for Containers | Per vCore/hour of AKS | Only if running AKS |

**Commonly overpaid scenarios:**
- Defender for Servers Plan 2 deployed on dev/test VMs where Plan 1 suffices
- Defender for SQL enabled on subscriptions with no SQL resources
- Defender for Storage (Classic) on high-transaction storage accounts
- Defender for App Service on every plan including dev/test

```powershell
# List all Defender plans per subscription
foreach ($sub in $subList) {
    Write-Host "=== Subscription: $sub ==="
    az security pricing list --subscription $sub --output json | ConvertFrom-Json |
        Where-Object { $_.pricingTier -eq 'Standard' } |
        Select-Object name, pricingTier, subPlan
}
```

---

## RECOVERY SERVICES VAULTS / BACKUP

### Backup Cost Drivers

| Driver | Detail |
|---|---|
| Backup storage type | GRS vault = 2× cost of LRS vault. Default is GRS. If DR not required or data is replicated by other means, switch to LRS. Cannot change after first backup is configured — must stop and reconfigure. |
| Snapshot retention (instant recovery) | VM backup instant snapshots retained for 1-7 days, charged at Premium SSD price. Default 2 days is usually sufficient. |
| Long-term retention policies | Weekly/monthly/yearly recovery points retained for years. Each additional policy tier adds cost. Reduce where SLA doesn't require it. |
| Cross-region restore (CRR) enabled | Small additional cost on GRS vaults. Allows restore to secondary region without declaring disaster. Usually worth keeping if GRS is already enabled. |
| Unnecessary backup items | FSLogix profile disks, ASR cache storage accounts, temp disks — these are often backed up but should not be. |

### What Gets Billed

- Protected instance fee: per-instance monthly charge based on VM disk size tier
- Backup storage: per GB stored in vault (GRS = charged for both primary and secondary)
- Instant recovery snapshots: per GB at Premium SSD snapshot pricing (regardless of original disk tier)
- Cross-region restore: additional storage and egress if actively used

### Common Waste Patterns

```powershell
# Find Recovery Services Vaults and their SKU (geo-redundancy)
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.recoveryservices/vaults' | project name, resourceGroup, subscriptionId, sku_name=sku.name, storageType=properties.storageTypeDetails" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

---

## API MANAGEMENT

### Tier Comparison

| Tier | Monthly Cost | SLA | Use Case |
|---|---|---|---|
| Consumption | ~£0 (pay per 10K calls) | 99.95% | Low-volume APIs, dev/test, event-driven |
| Developer | ~£40/month | **No SLA** | Dev/test only — **never production** |
| Basic v2 | ~£110/month | 99.95% | Low-medium production APIs |
| Standard v2 | ~£550/month | 99.95% | Medium production, VNet support |
| Premium v2 | ~£1,800/month/unit | 99.99% | Multi-region, high scale |

- Developer tier has no SLA — if it's serving production traffic, this is both a cost and risk issue
- Consumption tier: first 1M calls/month free; charged per 10K calls above that — excellent for low-volume
- Premium tier: very expensive; check if multi-region capabilities or >99.95% SLA is genuinely needed
- v2 tiers (Basic v2, Standard v2, Premium v2): newer, more cost-effective than v1 equivalents

```powershell
# Find APIM instances and their tiers
az graph query -q "resources | where subscriptionId in ($subs) | where type == 'microsoft.apimanagement/service' | project name, resourceGroup, subscriptionId, sku_name=sku.name, sku_capacity=sku.capacity, tags" --first 1000 --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

---

## LOG ANALYTICS — KQL COST INVESTIGATION QUERIES

### Identify Top Ingestion Sources

```kql
// Top 10 tables by ingestion volume (last 30 days)
Usage
| where TimeGenerated > ago(30d)
| summarize TotalGB = sum(Quantity) / 1000 by DataType
| top 10 by TotalGB desc
| render barchart
```

```kql
// Find duplicate diagnostic settings (same table ingested from multiple sources)
Usage
| where TimeGenerated > ago(7d)
| where DataType in ("AzureDiagnostics", "AzureMetrics")
| summarize TotalGB = sum(Quantity) / 1000 by bin(TimeGenerated, 1d), DataType, Resource
| sort by TotalGB desc
```

```kql
// Application Insights: check for excessive dependency tracking
union AppDependencies, AppRequests, AppExceptions, AppTraces, AppPageViews
| where TimeGenerated > ago(7d)
| summarize EventCount = count(), EstimatedGB = count() * 1000.0 / 1000000 by itemType
| sort by EstimatedGB desc
```

```kql
// Check if commitment tier is being used effectively
Usage
| where TimeGenerated > ago(30d)
| summarize DailyGB = sum(Quantity) / 1000 by bin(TimeGenerated, 1d)
| summarize AvgDailyGB = avg(DailyGB), MaxDailyGB = max(DailyGB), MinDailyGB = min(DailyGB)
// If AvgDailyGB > 100 and on PAYG pricing, commitment tier is likely worth it
```

---

## AZURE ADVISOR — WHAT IT COVERS AND WHAT IT MISSES

### What Advisor Typically Catches

- VM rightsizing recommendations (based on 7-30 day CPU average)
- Unused Reserved Instances (purchased but not utilised)
- SQL Database unused for 7 days
- Unattached managed disks (may lag behind actual state)
- App Service Plan scaling opportunities
- Azure Hybrid Benefit not applied to eligible VMs
- Reserved Instance coverage recommendations

### What Advisor Typically Misses

- App Service Plans with very low utilisation that don't meet its specific threshold
- SQL Elastic Pools overprovisioned DTUs (Advisor focuses on individual databases)
- Service Bus namespace tier optimisation
- Defender for Cloud overprovisioning
- Log Analytics commitment tier opportunities (partially covered)
- Fabric capacity scheduling
- NAT Gateway idle charges
- DDoS Network Protection Plan (never flags this as it doesn't assess security costs)
- Private endpoint orphans
- Storage access tier misalignment
- Backup policy over-retention

```powershell
# Pull Azure Advisor cost recommendations for all subscriptions
$allAdvisorRecs = @()
foreach ($sub in $subList) {
    $recs = az advisor recommendation list --subscription $sub --category Cost --output json | ConvertFrom-Json
    $allAdvisorRecs += $recs | Select-Object *, @{Name='Subscription';Expression={$sub}}
}
$allAdvisorRecs | Select-Object Subscription, shortDescription, impactedValue, extendedProperties | Format-Table -AutoSize
```

---

## LESS OBVIOUS / OFTEN MISSED COST ITEMS

| Resource | Cost Driver | How to Find |
|---|---|---|
| Azure DDoS Network Protection Plan | ~£2,500+/month — often deployed and forgotten | `az graph query -q "resources \| where type == 'microsoft.network/ddosprotectionplans'"` |
| App Service Environment (empty) | Minimum charge even with zero apps | Check app count per ASE |
| Legacy Log Analytics pricing tier (Per Node) | Very complex, often more expensive than commitment tier | Check workspace pricing tier |
| Application Insights (Classic, not workspace-based) | Cannot use commitment tiers | `az graph query -q "resources \| where type == 'microsoft.insights/components' \| where properties.ingestionMode != 'LogAnalytics'"` |
| Azure Automation accounts | Runbooks and DSC node charges (usually small but worth checking in cost exports) | Cost export |
| Azure DNS Private Zones | Per zone + per million queries | Check for zones with zero query traffic |
| Azure Container Registry | Premium tier when Basic suffices; geo-replication enabled unnecessarily | `az graph query -q "resources \| where type == 'microsoft.containerregistry/registries'"` |
| Old/unused Azure DevOps parallel jobs | Paid parallel jobs at ~£33/job/month | Review in Azure DevOps organisation settings |
| Azure Static Web Apps | Standard plan ~£7/month; if traffic is low, Free tier may suffice | — |
| Idle Azure Spring Apps | Charged per vCore-hour even when idle | Check deployment state |
| Azure Data Factory Integration Runtimes | Self-hosted IRs: small hourly charge if running 24/7 | Check IR activity |
| Azure Logic Apps Integration Accounts | Standard tier ~£250/month; Free tier has entity limits | `az graph query -q "resources \| where type == 'microsoft.logic/integrationaccounts'"` |
| ExpressRoute circuits in provisioned state | Charged monthly even if not connected to a router | Check circuit state (Provisioned vs NotProvisioned) |

---

## RESERVED INSTANCES & SAVINGS PLANS — QUICK REFERENCE

| Resource | RI Available | Savings Plan Available | Max Saving |
|---|---|---|---|
| Azure VMs | ✅ | ✅ Compute Savings Plan | ~60% (3yr RI) |
| App Service P3v3 | ✅ | ❌ | ~55% (3yr) |
| App Service Isolated (ASE Iv2) | ✅ | ❌ | ~55% (3yr) |
| Azure SQL Elastic Pools (provisioned) | ✅ | ❌ | ~56% (3yr) |
| Azure SQL Single Databases (provisioned) | ✅ | ❌ | ~56% (3yr) |
| Azure SQL Serverless | ❌ | ❌ | — |
| Azure SQL VMs | ✅ (for compute) | ✅ | ~60% (3yr) |
| Azure Database for PostgreSQL/MySQL | ✅ | ❌ | ~55% (3yr) |
| Cosmos DB | ✅ | ❌ | ~65% (3yr) |
| Azure Dedicated Hosts | ✅ | ❌ | ~45-60% |
| Azure Blob Storage | ✅ (capacity reservations) | ❌ | ~15% |

**RI vs Savings Plan guidance:**
- Use RIs for: stable workloads with predictable size and location (e.g. production SQL, production App Service P-tier)
- Use Compute Savings Plans for: variable VM fleets, planned resize/migration, mixed workloads
- Always check existing RI coverage/utilisation before purchasing new: unused RIs are wasted commitment

**Full list of RI-supported Azure services:**
VMs, Azure SQL DB / SQL MI, Azure SQL VMs (compute), Cosmos DB, Blob Storage / Data Lake Gen2, Azure Files, Managed Disks (Premium SSD P30+), Databricks, App Service (Isolated stamp), Dedicated Host, Cache for Redis, MySQL / PostgreSQL, Synapse Analytics, Data Factory, AKS node VMs, VMware Solution, NetApp Files, Red Hat OpenShift, SUSE Linux plans, Data Explorer, Microsoft Fabric.

**Viewing unused reservation spend (amortized cost view):**

1. Cost Analysis → set metric to **Amortized Cost**
2. Add filter: **Pricing Model = Reservation**
3. Group by: **Charge Type** — look for `unusedreservation` rows
4. This is the monetary value of reserved capacity paid for but not consumed

**RI utilisation via CLI:**

```bash
# List all reservations
az reservations reservation list-all --output table

# Monthly utilisation summary for a specific reservation order
az consumption reservation summary list \
  --grain monthly \
  --reservation-order-id {reservationOrderId} \
  --output table

# Advisor recommendations for underutilised reservations
az advisor recommendation list --category Cost \
  --query "[?contains(shortDescription.problem, 'reservation')]" \
  --output table
```

**Break-even rule of thumb:**

- VM runs >70% of hours/month → RI is worth buying
- VM runs <50% of hours/month → pay-as-you-go or Spot
- Always check RI coverage before following an Advisor right-size recommendation — resizing to a different SKU family may break the RI mapping and increase cost

---

## AZURE HYBRID BENEFIT — DETAILED CLI COMMANDS

### Enable AHB on VMs

```bash
# Enable AHB on a single VM
az vm update --resource-group myRG --name myVM --set licenseType=Windows_Server

# Enable AHB on a VMSS
az vmss update --resource-group myRG --name myVMSS \
  --set virtualMachineProfile.licenseType=Windows_Server

# List all VMs and their current AHB status
az vm list --query "[].{Name:name, RG:resourceGroup, License:licenseType}" --output table

# Find Windows VMs NOT using AHB (missing or incorrect licenceType)
az graph query -q "resources | where type == 'microsoft.compute/virtualmachines' | where properties.storageProfile.osDisk.osType == 'Windows' | where isempty(properties.licenseType) or properties.licenseType != 'Windows_Server' | project name, resourceGroup, subscriptionId, vmSize=properties.hardwareProfile.vmSize" --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

**For Linux (RHEL / SUSE):** Use `licenseType = RHEL_BYOS` or `licenseType = SLES_BYOS`. Requires active Red Hat / SUSE subscriptions.

**AHB savings summary:**

- Windows Server VMs: ~40% off the OS licence component (compute price drops to Linux rate)
- SQL Server in Azure SQL / SQL MI: up to 55% combined with 3-year RI
- Minimum licence requirement: 8 core licences with active Software Assurance per VM

---

## ADDITIONAL RESOURCE GRAPH KQL QUERIES

### Stopped-but-Not-Deallocated VMs (Still Paying for Compute)

> A VM in "Stopped" state (OS shutdown) still incurs compute charges. Only "Deallocated" stops billing. This is one of the most commonly missed waste areas.

```kusto
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| where properties.extended.instanceView.powerState.displayStatus =~ 'VM stopped'
| project name, resourceGroup, location,
          vmSize = tostring(properties.hardwareProfile.vmSize),
          powerState = tostring(properties.extended.instanceView.powerState.displayStatus),
          id
```

### Resources With No Tags

```kusto
// All untagged resources
Resources
| where isnull(tags) or tags == "{}"
| project name, type, resourceGroup, subscriptionId
| order by type asc
```

```kusto
// Untagged VMs and Storage Accounts only
Resources
| where type in~ ('microsoft.compute/virtualmachines', 'microsoft.storage/storageaccounts')
| where isnull(tags) or tags == "{}"
| project name, type, resourceGroup, subscriptionId
```

```kusto
// Inventory all tag keys and values in use (useful to assess tagging maturity)
union
(Resources | where isnotempty(tags) | project tags),
(ResourceContainers | where isnotempty(tags) | project tags)
| mvexpand tags
| extend tagKey = tostring(bag_keys(tags)[0])
| extend tagValue = tostring(tags[tagKey])
| distinct tagKey, tagValue
| where tagKey !startswith "hidden-"
```

### Old Snapshots (>90 Days)

```kusto
Resources
| where type =~ 'microsoft.compute/snapshots'
| extend ageInDays = datetime_diff('day', now(), todatetime(properties.timeCreated))
| where ageInDays > 90
| project name, resourceGroup, location,
          ageInDays,
          sizeGB = tostring(properties.diskSizeGB),
          storageType = tostring(sku.name),
          id
| order by ageInDays desc
```

```kusto
// Snapshots on Premium storage (switch to Standard = ~60% saving)
Resources
| where type =~ 'microsoft.compute/snapshots'
| where sku.name =~ 'Premium_LRS'
| project name, resourceGroup, location,
          sizeGB = tostring(properties.diskSizeGB), id
```

### Orphaned Network Security Groups (Not Associated to Any NIC or Subnet)

```kusto
Resources
| where type =~ "microsoft.network/networksecuritygroups"
| where isnull(properties.networkInterfaces)
| where isnull(properties.subnets)
| project name, resourceGroup, location, id
| sort by name asc
```

### VPN Gateways With No Connections

```kusto
Resources
| where type =~ 'microsoft.network/virtualnetworkgateways'
| where properties.gatewayType =~ 'Vpn'
| join kind=leftouter (
    Resources
    | where type =~ 'microsoft.network/connections'
    | extend gatewayId = tostring(properties.virtualNetworkGateway1.id)
    | summarize connectionCount = count() by gatewayId
) on $left.id == $right.gatewayId
| where isnull(connectionCount) or connectionCount == 0
| project name, resourceGroup, location,
          sku = tostring(properties.sku.name), id
```

### Empty Resource Groups

```kusto
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions/resourcegroups'
| join kind=leftouter (
    Resources
    | summarize resourceCount = count() by resourceGroup
) on $left.name == $right.resourceGroup
| where isnull(resourceCount) or resourceCount == 0
| project name, location, subscriptionId
```

### DDoS Protection Plans With No Associated VNets

```kusto
Resources
| where type =~ 'microsoft.network/ddosprotectionplans'
| project name, resourceGroup, location,
          virtualNetworks = array_length(properties.virtualNetworks), id
| where isnull(virtualNetworks) or virtualNetworks == 0
```

### DNS Zones With Only Default Records (Effectively Empty)

```kusto
Resources
| where type =~ 'microsoft.network/dnszones'
| extend recordCount = properties.numberOfRecordSets
| project name, resourceGroup, location, recordCount, id
| where recordCount <= 2  // Only SOA + NS = likely unused
```

### Union Query — All Orphaned Resources in One Shot

```kusto
union
(Resources | where type =~ 'microsoft.compute/disks' | where properties.diskState =~ 'Unattached' | where managedBy == "" | project name, type, resourceGroup, location, wasteCause="Unattached Disk"),
(Resources | where type =~ 'microsoft.network/publicipaddresses' | where isnull(properties.ipConfiguration) | where isnull(properties.natGateway) | project name, type, resourceGroup, location, wasteCause="Unused Public IP"),
(Resources | where type =~ 'microsoft.network/loadbalancers' | where array_length(properties.backendAddressPools) == 0 | project name, type, resourceGroup, location, wasteCause="Empty Load Balancer"),
(Resources | where type =~ 'microsoft.web/serverfarms' | where properties.numberOfSites == 0 | project name, type, resourceGroup, location, wasteCause="Empty App Service Plan"),
(Resources | where type =~ 'microsoft.network/networksecuritygroups' | where isnull(properties.networkInterfaces) and isnull(properties.subnets) | project name, type, resourceGroup, location, wasteCause="Orphaned NSG"),
(Resources | where type =~ 'microsoft.network/natgateways' | where array_length(properties.subnets) == 0 | project name, type, resourceGroup, location, wasteCause="Unused NAT Gateway"),
(Resources | where type =~ 'microsoft.network/ddosprotectionplans' | where array_length(properties.virtualNetworks) == 0 | project name, type, resourceGroup, location, wasteCause="DDoS Plan - No VNets"),
(Resources | where type =~ 'microsoft.compute/snapshots' | where datetime_diff('day', now(), todatetime(properties.timeCreated)) > 90 | project name, type, resourceGroup, location, wasteCause="Old Snapshot (>90d)")
| order by wasteCause asc
```

---

## AZURE COST MANAGEMENT — COST ANALYSIS TECHNIQUES

### Finding Waste in Cost Analysis

| View / Filter | What to Look For |
|---|---|
| **Daily granularity, last 3 months** | Spikes on specific days = new deployments or auto-scaling events |
| **Group by: Resource Group** | Identify RGs with unexpected growth |
| **Group by: Resource** | Highest-cost individual resources |
| **Group by: Service Name** | Services costing more than expected |
| **Amortized cost + Group by: Charge Type** | Look for `unusedreservation` = wasted RI/Savings Plan spend |
| **Filter: Pricing Model = Reservation** | RI utilisation; `unusedreservation` shows wasted hours |
| **Filter: Pricing Model = Spot** | Track Spot VM savings vs interruption costs |

**Workflow for investigating a cost spike:**

1. Cost Analysis → Daily granularity → Last 3 months
2. Group by: Resource Group → find the spike RG
3. Drill in → Group by: Resource
4. Select the resource → Group by: Meter → exact SKU/tier causing the charge

### Anomaly Detection

- Azure Cost Management auto-detects anomalies at subscription level (not management group/RG level)
- Uses WaveNet deep learning, 60 days of historical data, runs ~36 hours after end of UTC day
- Up to 5 anomaly alert rules per subscription
- Government clouds: anomaly alerts NOT available for Azure Government

**Create an anomaly alert:**

1. Cost Management → Cost Alerts → **+ Add**
2. Alert type: **Anomaly**
3. Can trigger Action Groups for automated response (e.g., notify Teams, open ITSM ticket)

### Budget Alerts

```json
// PUT https://management.azure.com/subscriptions/{subId}/providers/Microsoft.Consumption/budgets/{name}/?api-version=2019-10-01
{
  "properties": {
    "category": "Cost",
    "amount": 10000,
    "timeGrain": "Monthly",
    "timePeriod": { "startDate": "2026-01-01T00:00:00Z", "endDate": "2027-01-01T00:00:00Z" },
    "notifications": {
      "Actual_GreaterThan_80_Percent": {
        "enabled": true,
        "operator": "GreaterThan",
        "threshold": 80,
        "thresholdType": "Actual",
        "contactEmails": ["finops@company.com"],
        "contactRoles": ["Owner", "Contributor"]
      },
      "Forecast_GreaterThan_100_Percent": {
        "enabled": true,
        "operator": "GreaterThan",
        "threshold": 100,
        "thresholdType": "Forecasted"
      }
    }
  }
}
```

Key: `thresholdType` can be `Actual` (current spend) or `Forecasted` (projected). Alerts evaluate once per day. Can filter by resource group, meter, or tags. Budget actions can auto-shutdown VMs when 90% consumed.

---

## AZURE ADVISOR — FULL COVERAGE REFERENCE

### Full List of Cost Recommendations Advisor Produces

| Service | Recommendation |
|---|---|
| **App Service** | Empty plans (no apps); underutilised plans (low CPU 7d) |
| **Application Gateway / Front Door** | Disable health probes (single origin); migrate Front Door Classic to Standard/Premium |
| **Cosmos DB** | Enable autoscale; idle containers (30d); MongoDB v4.2 migration (55% storage saving) |
| **Azure Data Explorer** | Cost-effective SKU; autoscale; delete stopped clusters (60d); reduce cache policy |
| **MySQL / PostgreSQL** | Right-size underutilised servers (7d low utilisation) |
| **Azure Databricks** | Enable autoscaling for clusters |
| **AKS** | VPA recommendation mode; Spot nodes; aggressive cluster autoscaler; Prometheus-based metrics (up to 80% cheaper than Log Analytics) |
| **Azure Monitor / Log Analytics** | Ingestion anomaly; Basic logs plan (>1 GB/month tables); commitment tier change |
| **Azure Synapse** | Enable automatic pause for Spark; enable autoscale for Spark |
| **Data Factory** | Delete failing pipelines (billed while failing) |
| **Virtual Machines** | Unattached disks; Premium→Standard snapshots (**High impact, ~60% saving**); right-size/shutdown (CPU P95 <3%, outbound <2% over lookback); burstable SKU for spiky workloads |
| **Storage** | Classic log data retention; Premium storage for high-transaction/TB workloads |
| **Reserved Instances** | VMs, SQL PaaS, Cosmos DB, App Service, Data Factory, Managed Disks, Blob Storage, Redis, MySQL/PostgreSQL, Synapse, Fabric, Savings Plan for Compute — all **High impact** |

**Advisor lookback limitation:** Default 7-day lookback for VM recommendations. VMs shut down for >1 day in 7 may produce no recommendation.
**Advisor savings figures use retail rates** — actual savings with EA/MCA discounts will differ.

### What Advisor Does NOT Flag (Confirmed Gaps)

| Category | Gap |
|---|---|
| **Network resources** | Unused VPN Gateways with no connections, unused NAT Gateways, orphaned NSGs |
| **Public IPs** | Unassociated public IPs (not flagged for deletion) |
| **DDoS Protection Plans** | Never flagged (very expensive, ~$2,944/month) |
| **App Service Environments** | Idle ASE v3 (still charges for minimum I1v2 instance) |
| **Load Balancers** | Empty load balancers with no backend pool members |
| **Application Gateways** | Gateways with empty backend pools |
| **Orphaned snapshots** | Old/large snapshots (partial: only flags Premium→Standard) |
| **Empty resource groups** | Not flagged |
| **Duplicate diagnostics** | Doesn't identify the same data ingested twice |
| **Application Insights** | Doesn't flag components with no recent data; no daily cap warning |
| **Stopped (not deallocated) VMs** | May miss: a stopped VM has 0% CPU, so no utilisation-based recommendation |
| **DNS zones** | Per-zone charges on idle/empty zones not flagged |
| **RI cross-series risk** | Explicitly warns that right-size recommendations don't account for existing RIs |

### Export Advisor Recommendations via CLI

```bash
# All cost recommendations for a subscription
az advisor recommendation list --category Cost --output table

# Export with savings amount
az advisor recommendation list --category Cost \
  --query "[].{Name:name, Impact:impact, Resource:resourceMetadata.resourceId, Savings:extendedProperties.savingsAmount}" \
  --output table

# PowerShell: export all recs across multiple subscriptions
$allAdvisorRecs = @()
foreach ($sub in $subList) {
    $recs = az advisor recommendation list --subscription $sub --category Cost --output json | ConvertFrom-Json
    $allAdvisorRecs += $recs | Select-Object *, @{Name='Subscription';Expression={$sub}}
}
$allAdvisorRecs | Select-Object Subscription, shortDescription, impactedValue, extendedProperties | Format-Table -AutoSize
```

---

## AZURE POLICY — COST GOVERNANCE

### Built-in Tag Enforcement Policies

| Policy | Effect | Description |
|---|---|---|
| `Require a tag on resources` | Deny | Requires a specific tag key on all resources |
| `Require a tag and its value on resources` | Deny | Requires a specific tag key-value pair |
| `Inherit a tag from the resource group` | Modify | Appends tag from RG if resource lacks it |
| `Inherit a tag from the subscription` | Modify | Appends tag from subscription if resource lacks it |
| `Add or replace a tag on resources` | Modify | Forces a tag key-value regardless of existing value |

```bash
# Assign "Require a tag" at subscription scope
az policy assignment create \
  --name "require-costcentre-tag" \
  --display-name "Require CostCentre tag on all resources" \
  --policy "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99" \
  --scope "/subscriptions/{subscriptionId}" \
  --params '{"tagName": {"value": "CostCentre"}}'
```

### Restrict VM SKUs (Prevent Expensive Deployments)

```bash
# Built-in policy: Allowed virtual machine size SKUs
# Policy ID: cccc23c7-8427-4f53-ad12-b6a63eb452b3
az policy assignment create \
  --name "restrict-vm-skus" \
  --policy "cccc23c7-8427-4f53-ad12-b6a63eb452b3" \
  --scope "/subscriptions/{subscriptionId}" \
  --params '{
    "listOfAllowedSKUs": {
      "value": ["Standard_B2ms", "Standard_B4ms", "Standard_D2s_v5",
                "Standard_D4s_v5", "Standard_D8s_v5", "Standard_E4s_v5"]
    }
  }'
```

### Restrict Deployment Locations

```bash
# Built-in policy: Allowed locations
# Policy ID: e56962a6-4747-49cd-b67b-bf8b01975c4c
az policy assignment create \
  --name "restrict-locations" \
  --policy "e56962a6-4747-49cd-b67b-bf8b01975c4c" \
  --scope "/subscriptions/{subscriptionId}" \
  --params '{"listOfAllowedLocations": {"value": ["uksouth", "ukwest"]}}'
```

### Recommended Cost Governance Policy Initiative

Combine into a custom Policy Set (Initiative):

1. Require tags: `Environment`, `CostCentre`, `Owner`
2. Inherit tags from resource group
3. Allowed VM SKUs (exclude GPU/HPC from non-production)
4. Allowed locations (prevent accidental deployments in expensive regions)
5. Audit VMs without Azure Hybrid Benefit enabled (custom policy)
6. Deny DDoS Protection Plan deployments without approval (custom deny)
7. Require App Service to use B-series or above (deny Free/Shared in production)

### Audit Non-Compliant Resources

```bash
az policy state list \
  --scope "/subscriptions/{subscriptionId}" \
  --filter "complianceState eq 'NonCompliant'" \
  --query "[].{Resource: resourceId, Policy: policyDefinitionName, RG: resourceGroup}" \
  --output table
```

---

## OPEN SOURCE AND THIRD-PARTY TOOLS

### Azure Optimization Engine (Microsoft Open Source)

- **Repo:** <https://github.com/Azure/Azure-Optimization-Engine>
- **Deployment:** Azure Automation Account + Logic Apps + Log Analytics
- **What it does:** Collects inventory and consumption data; generates recommendations beyond Advisor — orphaned resources, underutilised resources, RI/Savings Plan opportunities; workbook dashboards; scheduled runs with alerting
- **Cost:** Free (infrastructure ~$30–50/month to run)

### Commercial Tools

| Tool | Vendor | Strength |
|---|---|---|
| Cloudability | Apptio (IBM) | Enterprise FinOps, chargeback, forecasting, multi-cloud |
| CloudHealth | VMware (Broadcom) | Multi-cloud governance, showback/chargeback |
| Spot.io | NetApp | Spot/Preemptible VM automation, Ocean for Kubernetes |
| Kubecost | Kubecost | AKS namespace-level cost visibility |
| Infracost | Open source | Cost estimation in CI/CD pipelines (Terraform/Bicep) |
| Cloud Custodian | Open source | Policy-as-code engine with Azure provider |

---

## ENGAGEMENT PRIORITY ORDER — EFFORT vs SAVINGS

For a new customer, work through in this sequence:

| Priority | Action | Tool | Typical Saving |
| --- | --- | --- | --- |
| 1 | Run Azure Advisor → export all Cost recommendations | Portal / CLI | Variable, quick wins |
| 2 | Run union orphan KQL query (disks, IPs, NSGs, App Service Plans, NAT GWs) | Resource Graph | £100–£10,000+/month |
| 3 | Check for stopped-but-not-deallocated VMs | Resource Graph | Variable |
| 4 | Review unused RI spend (amortized cost, `unusedreservation` charge type) | Cost Analysis | Can be significant |
| 5 | Check DDoS Protection Plans — is one actually needed? | Resource Graph | ~£2,000–3,000/month each |
| 6 | Check Azure Hybrid Benefit coverage for Windows VMs and SQL | CLI | 30–40% of Windows VM costs |
| 7 | Review Log Analytics ingestion by table (top 10 tables) | Log Analytics KQL | £500–£5,000+/month |
| 8 | Review ASE, ARO, Service Bus Premium for idle/over-provisioned environments | Resource Graph | £1,000s/month |
| 9 | Review Application Insights sampling and daily caps | App Insights portal | Variable |
| 10 | VPN Gateways with no connections, old snapshots, DNS zones, Front Door WAF | Resource Graph | Variable |
| 11 | Establish tag policy and budget alerts for ongoing governance | Azure Policy | Prevents future waste |

---

## DIAGNOSTIC SETTINGS — DEFAULT VERBOSITY AND LOG ANALYTICS COST

The most commonly reported community finding: **default diagnostic settings are configured for maximum visibility, not cost**. Services are "incredibly chatty" by default and can make Log Analytics the most expensive line item on the bill — exceeding compute costs.

| Service | Default Setting | What It Generates |
| --- | --- | --- |
| **App Service** | AllLogs enabled | Every health probe hit (e.g., load balancer pinging /health every 5s = 17,000+ entries/day per instance) |
| **Azure Firewall** | AllLogs enabled | Every allowed packet, DNS proxy query, application rule match — can be millions of rows/hour |
| **Azure Key Vault** | AllMetrics enabled | All metrics including heartbeat; typically only `AuditEvent` is needed |
| **Storage Accounts** | Logging all reads | Every successful GET request logged; high-read workloads generate huge volumes |
| **NSGs** | Flow logs enabled + Traffic Analytics | Flow log storage charges + Log Analytics ingestion charges + Traffic Analytics processing charge |

**Approach:** Review each resource's diagnostic settings. Set explicit categories rather than `allLogs` / `allMetrics`. For Azure Firewall in particular, consider using a separate low-cost workspace or Auxiliary Logs table for the high-volume rule match logs, and only sending audit/security events to the main workspace.

### Azure Firewall Logging in Detail

Azure Firewall with `allLogs` sends:

- `AzureFirewallApplicationRule` — every application rule match
- `AzureFirewallNetworkRule` — every network rule match
- `AzureFirewallDNSProxy` — every DNS query routed through the firewall
- `AzureFirewallThreatIntelLog` — threat intelligence hits

In a busy environment this is **hundreds of GB of ingestion per day**. The Firewall itself may cost £1,000–2,000/month; the logging can cost the same again.

**Recommendation:** Log only `AzureFirewallThreatIntelLog` and `AzureFirewallApplicationRule` (deny actions) to the main workspace. Route allow-rule logs to a Basic Logs table (pay-per-query only — drastically cheaper for rarely-queried data).

### List All Diagnostic Settings Across a Subscription

```bash
# List all diagnostic settings for every resource in a subscription
az monitor diagnostic-settings list --resource /subscriptions/{subId} --output table

# Find resources sending to Log Analytics (to identify scope of the problem)
az graph query -q "resources | where type == 'microsoft.insights/diagnosticsettings' | extend workspaceId = tostring(properties.workspaceId) | where isnotempty(workspaceId) | project name, resourceGroup, workspaceId, id" --output json | ConvertFrom-Json | Select-Object -ExpandProperty data
```

Source: [What's the Most Unexpectedly Expensive Thing in Your Azure Bill — DEV Community](https://dev.to/techresolve/solved-whats-the-most-unexpectedly-expensive-thing-in-your-azure-bill-lately-1p4d)

---
