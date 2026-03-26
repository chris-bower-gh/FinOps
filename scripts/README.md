# FinOps Scripts Library

Reusable scripts for Azure cost optimisation engagements run by Synextra. All scripts are parameterised and can be reused across any customer engagement.

---

## Engagement Methodology

Cost optimisation engagements follow three phases, always completed in order:

### Phase 1 — Cost Export Analysis

Manual CSV download from the Azure Portal (Cost Management + Billing → Cost Analysis). No scripting is possible for this phase. The cost exports are used to identify which services are driving spend before any resource data is collected. This prevents wasted effort collecting inventory for low-cost services and surfaces unexpected cost drivers (e.g., Defender charges appearing under a different resource type).

### Phase 2 — Resource Inventory and Configuration Collection

KQL queries run in Azure Resource Graph Explorer, and PowerShell scripts using the Azure CLI (`az`), collect resource inventory and configuration data. This phase establishes what is deployed and how it is configured.

### Phase 3 — Utilisation Metrics Collection

Azure Monitor metrics are collected via PowerShell (`az monitor metrics list`). Log Analytics usage queries are run directly in Log Analytics workspaces via the portal.

**Two-stage approach for right-sizing:** Initial screen scripts use 30-day hourly averages to identify candidates efficiently. For any flagged resource, run the corresponding `-deepdive` script (7-day 1-minute granularity) before making a recommendation — hourly averages mask short-duration spikes such as scheduled batch jobs.

---

## How to Use These Scripts

### KQL files

Run KQL files in **Azure Resource Graph Explorer**: portal.azure.com → search "Resource Graph Explorer". KQL files in `phase3-utilisation/` that target Log Analytics usage data must be run in the relevant **Log Analytics workspace → Logs** blade instead.

### PowerShell scripts

Before running any PowerShell script:

1. Populate `config.ps1` with the customer's subscription IDs and resource details.
2. Ensure `az login` has been completed and you have appropriate subscription access.
3. Output CSV files are written to the path set in `$outputDir` in `config.ps1`.

---

## Script Index

### phase2-inventory/

| File | Description |
| --- | --- |
| `01-sql-elastic-pools.kql` | SQL Elastic Pools — inventory with edition, DTU/vCore capacity, storage, and zone redundancy |
| `01-sql-elastic-pools-server-names.kql` | SQL Elastic Pools — returns server names needed to build metric resource IDs |
| `02-virtual-machines.kql` | Virtual Machines — inventory with VM size and power state |
| `02-vm-autoshutdown.kql` | VM auto-shutdown schedules — time, timezone, and enabled status |
| `03-managed-disks.kql` | Managed Disks — inventory with SKU, size, and attachment status |
| `04-app-service-plans.kql` | App Service Plans — inventory with SKU tier, OS, app count, and worker count |
| `05-service-bus.kql` | Service Bus namespaces — inventory with tier, SKU, and capacity |
| `06-virtual-network.kql` | Virtual Network resources — peerings, public IPs, load balancers, NAT gateways, private endpoints |
| `07-storage-accounts.kql` | Storage Accounts — inventory with SKU, kind, and access tier |
| `08-azure-firewall.kql` | Azure Firewall — tier (Standard/Premium) and policy linkage |
| `08-azure-firewall-diagnostics.ps1` | Azure Firewall — retrieves diagnostic settings via CLI (Resource Graph does not reliably return these) |
| `09-microsoft-fabric.kql` | Microsoft Fabric Capacities — SKU and running/paused state |
| `09-fabric-pause-schedule.kql` | Checks for Automation Runbooks or Logic Apps that pause/resume Fabric capacity |
| `10-log-analytics.kql` | Log Analytics Workspaces — SKU, retention period, and daily quota |
| `10-app-insights.kql` | Application Insights instances — workspace linkage and retention (flags DefaultWorkspace usage) |
| `11-virtual-wan.kql` | Virtual WAN — hubs, VPN gateways, and P2S gateways with provisioning state |
| `12-data-factory.kql` | Data Factory instances — provisioning state |
| `12-data-factory-ir.ps1` | Data Factory — Integration Runtime types (Managed VNET IR vs Azure IR vs Self-Hosted) |
| `13-logic-apps.kql` | Logic Apps Standard — instances and their hosting App Service Plans |
| `14-defender-for-cloud.ps1` | Defender for Cloud — lists enabled Standard-tier plans per subscription |
| `15-app-gateway-frontdoor.kql` | Application Gateway — SKU, tier, and capacity |
| `15-frontdoor.kql` | Front Door profiles — SKU and provisioning state |
| `15-app-gateway-backends.kql` | Application Gateway — backend pool membership (identifies empty pools) |
| `16-backup-vaults.kql` | Recovery Services Vaults — redundancy settings (GRS vs LRS) and cross-region restore |
| `16-backup-retention.ps1` | Backup Vaults — retention periods per policy (daily, weekly, monthly, yearly) |
| `17-bastion.kql` | Azure Bastion — SKU tier (Developer/Basic/Standard) |
| `18-synapse.kql` | Synapse Analytics — workspaces, SQL pools, and Spark pools with auto-pause configuration |

### phase3-utilisation/

| File | Description |
| --- | --- |
| `01-sql-pool-metrics.ps1` | SQL Elastic Pools — 30-day hourly CPU/DTU % and storage % — **initial screen** |
| `01-sql-pool-metrics-deepdive.ps1` | SQL Elastic Pools — 7-day 1-minute DTU/CPU %, percentiles, spike detection — **run for all flagged pools** |
| `02-vm-metrics.ps1` | Virtual Machines — 30-day CPU % and available memory |
| `04-app-service-metrics.ps1` | App Service Plans — 30-day hourly CPU % and memory % — **initial screen** |
| `04-app-service-metrics-deepdive.ps1` | App Service Plans — 7-day 1-minute CPU % and memory %, absolute GB, headroom check — **run for all flagged plans** |
| `05-servicebus-metrics.ps1` | Service Bus — 30-day IncomingMessages, OutgoingMessages, ActiveMessages totals |
| `12-data-factory-pipeline-runs.ps1` | Data Factory — pipeline run counts, failure rate, and last status for the last 30 days |
| `log-analytics-ingestion-by-table.kql` | Log Analytics — billable ingestion in GB by table for the last 30 days (run per workspace) |
| `virtual-wan-hub-traffic.ps1` | Virtual WAN Hub — total data processed over 30 days to check if a hub is routing traffic |
