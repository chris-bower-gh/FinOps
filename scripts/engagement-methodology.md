# FinOps Engagement Methodology

## Overview

This methodology is used by Synextra to conduct Azure cost optimisation engagements. The process is structured into three phases, always completed in order. Scripts for phases 2 and 3 are in the subdirectories of this folder.

---

## Phase 1 — Cost Export Analysis

**Goal:** Understand what is actually driving cost before collecting any resource data.

**Why first:** Resource inventory alone does not reveal cost anomalies. Running cost-export analysis first prevents wasted data collection on low-spend services and reveals unexpected cost drivers (e.g., Defender for Storage appearing as a storage account cost).

**How to obtain cost exports:**

1. Azure Portal → Cost Management + Billing → Cost Analysis
2. Set scope to each subscription
3. Set view to "Cost by Resource" and date range to last full month
4. Download as CSV
5. Repeat for all subscriptions, saving files named by subscription

**What to look for:**

- Resources with unexpectedly high costs vs. their apparent function
- Meters that don't match the resource type (e.g., "Standard Node" under Storage = Defender for Storage)
- Non-prod resources with costs comparable to prod
- Resources with zero usage but ongoing charges

---

## Phase 2 — Resource Inventory and Configuration

**Goal:** For each significant cost area, understand what is deployed, how it is configured, and whether the configuration is justified.

**Scripts:** See subdirectories in `phase2-inventory/`

**Approach:**

1. Work through services in descending cost order
2. Run Resource Graph KQL queries in Azure Resource Graph Explorer (portal.azure.com → Resource Graph Explorer)
3. Run PowerShell scripts from a terminal with `az login` completed and appropriate subscription access
4. Save outputs to `<customer>/resource-data/` and `<customer>/metrics/`

**Key configuration checks per service type:**

| Service | Key Questions |
| --- | --- |
| SQL Elastic Pools | DTU vs vCore tier, utilisation %, storage %, empty pools |
| Virtual Machines | Size vs CPU/memory utilisation, auto-shutdown schedules |
| App Service Plans | SKU tier vs utilisation, OS type, app count per plan — **always use 04-app-service-plans.kql, not cost exports alone** |
| Service Bus | Premium vs Standard — Premium required for private endpoints; do not recommend downgrade if private endpoints are in use |
| Azure Firewall | Standard vs Premium tier, diagnostic settings verbosity |
| Microsoft Fabric | F-series vs P-series (F = pauseable), pause schedule present? |
| Log Analytics | PerGB2018 vs commitment tiers, DefaultWorkspace usage, daily caps |
| Virtual WAN | Hub count, traffic through each hub |
| Data Factory | Managed VNET IR vs standard Azure IR, pipeline run counts **and failure rate** |
| Logic Apps | Standard (WS1) plan count vs workflow density, utilisation |
| Defender for Cloud | Plans enabled per subscription, plans with no matching resources |
| App Gateway | WAF_v2 vs Standard_v2, especially in non-prod |
| Backup | GRS vs LRS vaults, retention period lengths |
| Bastion | Standard vs Basic vs Developer SKU |
| Synapse | Dedicated SQL pool vs Spark pool, auto-pause configured? |

---

## Phase 3 — Utilisation Metrics

**Goal:** Collect time-series utilisation data to support right-sizing and scheduling recommendations.

**Scripts:** See `phase3-utilisation/`

**Two-stage approach — follow this for SQL pools and App Service Plans:**

1. **Initial screen** — run the standard metrics script (30-day hourly averages) across all candidates. This identifies zero-utilisation resources and obvious over-provisioning efficiently.
2. **Deep-dive** — for every resource where a right-sizing recommendation will be made, run the corresponding `-deepdive` script (7-day 1-minute granularity). Populate `$sqlPoolsDeepDive` / `$appServicePlansDeepDive` in `config.ps1` first.

**Why two stages:** 30-day hourly averages mask short-duration bursts. A SQL pool at 6% average on hourly data can hit 400 DTU every day for 5 minutes (a scheduled batch job). A right-sizing recommendation based on the hourly average alone would cause daily throttling in production. The 1-minute data reveals the burst pattern and sets the safe threshold.

**Key utilisation queries:**

| Resource | Initial screen | Deep-dive | Tool |
| --- | --- | --- | --- |
| SQL Elastic Pools | `01-sql-pool-metrics.ps1` (30d hourly) | `01-sql-pool-metrics-deepdive.ps1` (7d 1-min) | PowerShell |
| App Service Plans | `04-app-service-metrics.ps1` (30d hourly) | `04-app-service-metrics-deepdive.ps1` (7d 1-min) | PowerShell |
| Virtual Machines | `02-vm-metrics.ps1` (30d hourly) | — | PowerShell |
| Service Bus | `05-servicebus-metrics.ps1` (30d totals) | — | PowerShell |
| Virtual WAN hubs | `virtual-wan-hub-traffic.ps1` (30d total) | — | PowerShell |
| Log Analytics workspaces | `log-analytics-ingestion-by-table.kql` | — | KQL (portal) |
| Data Factory | `12-data-factory-pipeline-runs.ps1` | — | PowerShell |

---

## Customer Folder Structure

For each engagement, create a folder: `<customer-name>/`

```text
<customer-name>/
  resource-data/        # CSV/JSON from Resource Graph and CLI inventory queries
  metrics/              # CSV from Azure Monitor metrics PowerShell scripts
  cost-exports/         # Cost export CSVs from Azure Portal
  analysis-notes/       # engagement-progress.md, cost-export-findings.md
  STATE.md           # Full context document for AI continuity
  report.md             # Final report (markdown)
  report.docx           # Final report (Word)
```

---

## Notes

- **AHB (Azure Hybrid Benefit)** is not in scope for Synextra engagements.
- **Indirect CSP billing**: Customers on indirect CSP have no API access to billing. Cost exports must be obtained manually from the portal.
- **Resource Graph limitations**: NIC attachment uses `properties.virtualMachine.id` not `properties.ipConfiguration.id`. Diagnostic settings are extension resources — use `az monitor diagnostic-settings list` not Resource Graph.
- **Service Bus naming**: Private endpoint resources (`microsoft.network/privateendpoints`) may be named similarly to Service Bus namespaces. Always verify resource type before analysis.
