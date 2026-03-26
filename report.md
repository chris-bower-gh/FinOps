# Azure Cost Saving Report

**Customer Name:** Cormar Carpets
**Order Type:** FinOps Review
**Provisioning Lead (Admin):** Chris Bower
**Provisioning Lead (Technical):** Chris Bower

---

## Revision History

| Version | Date | Author | Change Detail |
|---------|------|--------|---------------|
| 1.0 | March 2026 | Chris Bower | Initial draft |

---

## Table of Contents

1. [Overview](#overview)
2. [Findings](#findings)
   - [SQL Elastic Pools — £3,769/month](#1-sql-elastic-pools)
   - [Azure Firewall — £1,021/month](#2-azure-firewall)
   - [App Service Plans — £1,802/month](#3-app-service-plans)
   - [Log Analytics — £802/month](#4-log-analytics)
   - [Microsoft Fabric — £869/month](#5-microsoft-fabric)
   - [Virtual WAN — £754/month](#6-virtual-wan)
   - [Data Factory — £688/month](#7-data-factory)
   - [Logic Apps — £404/month](#8-logic-apps)
   - [Managed Disks — ASR Seed Disks](#9-managed-disks--asr-seed-disks)
   - [Application Gateway — £307/month](#10-application-gateway)
   - [Defender for Cloud — £363/month](#11-defender-for-cloud)
   - [Backup — £191/month](#12-backup)
   - [Bastion — £150/month](#13-bastion)
   - [Orphaned Public IP Addresses](#14-orphaned-public-ip-addresses)
   - [Virtual Machines — £275/month](#15-virtual-machines)
3. [Summary Table](#summary-table)

---

## Overview

This report has been produced by Synextra following a FinOps review of Cormar Carpets' Microsoft Azure estate. The purpose of the review is to evaluate Azure resource utilisation, pricing models, and configuration across the estate in order to identify opportunities where monthly cloud spend could be reduced without impacting operational capability. Findings are prioritised by potential saving and presented with a recommended remediation action and an implementation effort estimate.

The review covers 12 Azure subscriptions, with February 2026 costs used as the baseline for all spend figures. The approach taken was to begin with a cost export analysis to identify the highest-spending resource categories, followed by a resource inventory review and, where available, utilisation metrics over the 30-day period. Recommendations are grounded in observed data rather than general best practice alone, and where utilisation metrics or configuration details were not available, this is noted within the relevant finding.

---

## Findings

### 1. SQL Elastic Pools

Cormar Carpets operates 18 SQL elastic pools across production and non-production environments, with a combined monthly cost of £3,769.

| Pool | Tier | Capacity | 30d Avg% | 30d Max% | Action |
| --- | --- | --- | --- | --- | --- |
| cc-sqlep-b2b-dev | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-b2b-uat | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-b2c-uat | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-bhm-dev | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-bhm-uat | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-cstmr-dev | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-cstmr-uat | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-hm-dev | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-hm-uat | Standard | 50 DTU | 0% | 0% | Downgrade to Basic |
| cc-sqlep-staging-dev | Basic | 50 DTU | 0% | 0% | No action — already Basic |
| cc-sqlep-bhm-test | Standard | 50 DTU | 0% | 100% | No action — retained as-is |
| cc-sqlep-hm-test | Standard | 50 DTU | 0% | 12% | No action — retained as-is |
| cc-sqlep-staging-test | Standard | 50 DTU | 0% | 53% | No action — retained as-is |
| cc-sqlep-b2b-test | Standard | 100 DTU | 0.1% | 58.6% | No action — retained as-is |
| sqlep-cormar-common-dmz-prod-uks-001 † | Standard | 400 DTU | 6% (30d avg) | business-hours P99=44 eDTU | Right-size to 100 DTU |
| sqlep-cormar-common-prod-uks-001 † | General Purpose | 4 vCore | 4.8% | 89% peak | No action — correctly sized |

† 7-day 1-minute metrics analysed — see detail below

#### Non-production pools — idle compute

30-day utilisation metrics show nine non-production pools recorded 0% average DTU consumption — not low utilisation, but zero activity throughout the entire measurement window. All nine are provisioned at 50 DTU Standard while remaining completely idle.

A further four non-prod pools show minimal but non-zero activity:

- `cc-sqlep-bhm-test-uks-001` — spikes to 100% max, averages 0%
- `cc-sqlep-hm-test-uks-001` — peaks at 12%
- `cc-sqlep-staging-test-uks` — peaks at 53%
- `cc-sqlep-b2b-test-uks-001` (100 DTU Standard) — peaks at 58.6%, averages 0.1%

These patterns indicate infrequent short-duration bursts rather than sustained load. All four are retained as-is.

Each pool exists within its own environment lane as part of the estate's deliberate network segregation — dev, test, and UAT pools are not candidates for cross-environment consolidation.

The recommendation for the nine idle 50 DTU Standard pools is to downgrade to Basic tier. Basic carries a significantly lower per-eDTU cost, and the change is fully reversible — upgrading back to Standard requires only a brief connection interruption (typically under 30 seconds) with no data loss.

Before downgrading, verify for each pool:

- No individual database contains more than 2 GB of used data (Basic per-database storage ceiling)
- No databases contain columnstore indexes (unsupported in Basic tier)
- The application can tolerate the Basic tier's hard cap of 5 eDTU per database — any workload requiring per-database burst beyond 5 eDTUs (e.g. load tests, bulk imports) will be throttled

Upgrade back to Standard should be performed at the point each environment is activated for use.

#### Production pool — over-provisioned

`sqlep-cormar-common-dmz-prod-uks-001` is configured at 400 DTU Standard (~£290/month). Seven days of 1-minute granularity metrics (19–26 March 2026) were analysed. The pool is idle 59% of the time; P95 consumption is 20 eDTU, P99 is 32 eDTU, and business-hours P99 is 44 eDTU.

Every one of the 27 minutes across the 7-day window where the pool reached 400 eDTU followed an identical pattern: 06:16–06:20 UTC, every day including weekends. This is a scheduled batch job — not organic workload — and it is the sole justification for the current pool size. Outside this 4–5 minute daily window, the highest daytime organic spike observed was a single 1-minute burst of 260 eDTU.

Recommended two-stage approach for `sqlep-cormar-common-dmz-prod-uks-001`:

1. **Right-size immediately to 100 DTU Standard** — covers all business-hours organic load (P99 = 44 eDTU); reduces monthly cost from ~£290 to £75, saving £215/month. The 06:16 batch job will throttle to 100 DTU during its 4–5 minute window — confirm with the responsible team that this is acceptable for a background task.
2. **Investigate the 06:16 batch job** — its 4-minute burst profile running 7 days a week suggests an automated maintenance task (index rebuild or ETL). If it can be rate-limited or confirmed tolerant of 100 DTU, the pool could be reduced further to 50 DTU Standard.

`sqlep-cormar-common-prod-uks-001` (4 vCore GeneralPurpose) was reviewed separately using 7-day 1-minute CPU metrics:

- Average CPU 4.8%; idle more than 80% of the time
- Daily job at 07:02–07:08 UTC consistently peaks at 75–89% CPU
- On a 2 vCore pool (minimum GP size), this job would demand 150–178% of capacity — hard throttling every morning
- P99 demand across the 7-day window is 2.16 vCores

The current 4 vCore provisioning is appropriate. No right-sizing action is recommended for this pool.

##### Total monthly saving: £519

---

### 2. Azure Firewall

A single Azure Firewall, **cc-afw-prod-uks-001**, is deployed at the Premium tier as a Secured Virtual Hub integrated into the Virtual WAN:

- Premium tier cost: £906/month
- Data processing charges: £67/month
- **Total: ~£1,021/month**
- Diagnostic settings: correctly configured — Resource-Specific table mode, FatFlow and FlowTrace disabled, logs directed to **cc-log-azfwstructuredlogs-prod-uks-001**

The Premium tier is only justified if the following features are in active use:

- **IDPS** (Intrusion Detection and Prevention) — found to be **disabled** in the diagnostic settings review
- **TLS inspection** — enablement could not be confirmed as active during the review period
- **URL filtering** — enablement could not be confirmed as active during the review period

A Standard Secured Virtual Hub Firewall costs approximately £580/month, saving ~£320/month. Before downgrading, the Cormar IT team should confirm whether any of these three features are actively enforced or are part of a near-term security roadmap.

##### Total monthly saving: £310

---

### 3. App Service Plans

Across 36 App Service Plans, total monthly spend is £1,802, with non-production plans accounting for approximately £1,100. Several plans were found operating above Basic tier. Seven-day 1-minute CPU and memory metrics were analysed for each before any recommendation was made.

| Plan | SKU | OS | Apps | Action |
| --- | --- | --- | --- | --- |
| cc-asp-b2b-dev-uks-001 | P1v3 | Windows | 2 | Downgrade to B2 |
| cc-asp-b2b-test-uks-001 | B1 | Linux | 3 | No action |
| cc-asp-b2b-uat-uks-001 | B1 | Windows | 2 | No action |
| cc-asp-b2bv1-test-uks-001 | P0v3 | Windows | 2 | Downgrade to B1 |
| cc-asp-b2c-test-uks-001 | B1 | Windows | 1 | No action |
| cc-asp-b2c-uat-uks-001 | B1 | Windows | 1 | No action |
| cc-asp-bhm-dev-uks-001 | B1 | Linux | 2 | No action |
| cc-asp-bhm-test-uks-001 | B1 | Linux | 2 | No action |
| cc-asp-bhm-uat-uks-001 | B1 | Linux | 2 | No action |
| cc-asp-cstmr-dev-uks-001 | B1 | Linux | 3 | No action |
| cc-asp-cstmr-test-uks-001 | B2 | Linux | 4 | No action |
| cc-asp-cstmr-uat-uks-001 | B1 | Linux | 3 | No action |
| cc-asp-hm-dev-uks-001 | B1 | Linux | 1 | No action |
| cc-asp-hm-test-uks-001 | P0v3 | Linux | 1 | Downgrade to B1 |
| cc-asp-hm-uat-uks-001 | B1 | Linux | 1 | No action |
| cc-asp-qntum-dev-uks-001 | B1 | Windows | 1 | No action |
| cc-asp-qntum-test-uks-001 | B1 | Windows | 1 | No action |
| cc-asp-qntum-uat-uks-001 | B1 | Windows | 1 | No action |
| cc-aspfa-int-dev-uks | B1 | Linux | 2 | No action |
| cc-aspfa-int-test-uks | B1 | Linux | 2 | No action |
| cc-aspfa-int-uat-uks | B1 | Linux | 2 | No action |
| cc-aspfaahm-int-dev-uks | B1 | Linux | 1 | No action |
| cc-aspfaahm-int-test-uks | B1 | Linux | 1 | No action |
| cc-aspfabhm-int-dev-uks | B1 | Linux | 2 | No action |
| cc-aspfabhm-int-test-uks | P0v3 | Linux | 2 | Downgrade to B1 |
| cc-aspfacloud-int-dev-uks | B1 | Linux | 5 | No action |
| cc-aspfacloud-int-test-uks | B3 | Linux | 6 | Downgrade to B1 |
| cc-aspfawin-int-dev-uks | B1 | Windows | 12 | No action |
| cc-aspla-int-dev-uks | WS1 | Windows | 7 | No action — VNet isolation required |
| cc-aspla-int-test-uks | WS1 | Windows | 7 | No action — VNet isolation required |
| cc-aspla-int-uat-uks | WS1 | Windows | 7 | No action — VNet isolation required |
| plan-cormar-collectionpoints-prod-uks-001 | S2 | Windows | 7 | No action — at minimum viable size |
| plan-cormar-cormarapiwms-prod-uks-001 | S1 | Windows | 1 | No action |
| plan-cormar-internal-prod-uks-001 | P2v3 | Windows | 7 | Downgrade to P1v3 (monitor memory) |
| plan-cormar-sapphire-prod-uks-001 | S3 | Windows | 1 | Downgrade to S2 |
| plan-cormar-tradeportal-prod-uks-001 | P1v3 | Windows | 1 | No action — correctly sized |

#### Non-production plans — oversized SKUs

**cc-aspfacloud-int-test-uks** (B3) averages 6.4% CPU with a maximum of 71%. The equivalent dev environment, **cc-aspfacloud-int-dev-uks**, runs on B1 with similar workloads averaging 48% — well within B1 capability. Recommendation: downgrade to B1.

All four Premium V3 non-production plans run manual scale with no deployment slots — there is no feature-gate reason to remain on Premium.

**`cc-asp-b2bv1-test-uks-001`** (P0v3, Windows, 2 apps): Memory peak is 1,541 MB — within B1's 1.75 GB ceiling. CPU spikes that saturate the burstable 0.25 vCPU core translate to ~25% on B1's full vCPU. Downgrade to B1 is supported.

**`cc-asp-hm-test-uks-001`** (P0v3, Linux, 1 app): Memory peak is 896 MB — well within B1. CPU never exceeded 38% across the 7-day window. Downgrade to B1 is supported.

**`cc-aspfabhm-int-test-uks`** (P0v3, Linux, 2 apps): Memory peak is 1,147 MB — within B1. A single 53% CPU spike lasting one minute was the worst case observed; on B1's full vCPU this translates to ~13%. Downgrade to B1 is supported.

**`cc-asp-b2b-dev-uks-001`** (P1v3, Windows, 2 apps): Memory peak is 1.435 GB — fits within B1's 1.75 GB with 315 MB headroom. However, a recurring daily scheduled job fires at ~10:57–10:58 UTC and spikes CPU to 80–91% of the current 2 vCPU capacity every day. On a single-vCPU B1 this would translate to near-100% utilisation for 1–2 minutes, risking request queuing. Downgrade to B2 is recommended (2 vCPU, 3.5 GB RAM — same core count as P1v3, at significantly lower cost). B1 is not recommended without first identifying and resolving the 10:57 scheduled task.

#### Production plans

**`plan-cormar-internal-prod-uks-001`** (P2v3, Windows, 7 apps): P99 memory consumption is 2.88 GB and the observed peak is 3.12 GB — the next tier down is P1v3 at 3.5 GB, leaving only 380 MB headroom at the observed peak. CPU is not a concern — P99 is 27% of 2 vCPU and all spikes are 1–2 minute transients. A move from P2v3 to P1v3 is conditionally recommended, with a memory alert set at 80% (2.8 GB) immediately after migration and close monitoring for four weeks. If any hosted application is expected to grow in memory usage, or if additional applications are deployed to this plan, the move should not proceed.

**`plan-cormar-sapphire-prod-uks-001`** (S3, Windows, 1 app): Memory peak across 7 days was 3.15 GB — this rules out S1 and B1 (both 1.75 GB) but fits within S2's 3.5 GB, leaving ~350 MB headroom. A confirmed daily scheduled job fires at 10:45–10:46 UTC every day including weekends, reaching 97–100% of the current 4 vCPU capacity for 1–2 minutes. On S2 (2 vCPU), this burst would take 2–4 minutes. Downgrade from S3 to S2 is recommended, subject to confirming that the 10:45 job is not latency-sensitive.

**`plan-cormar-collectionpoints-prod-uks-001`** (S2, Windows, 7 apps): This plan is at its minimum viable size — CPU P99 is 92% of 2 vCPU, with 100% saturation events observed, and memory P99 is 2.8 GB with a peak of 3.255 GB. No downgrade is recommended; any further load growth would indicate a need to scale up.

#### plan-cormar-tradeportal-prod-uks-001 — no right-sizing opportunity

Seven days of 1-minute CPU metrics were analysed. Average CPU is 7.9% but spikes to 90–100% are frequent during business hours, driven by a confirmed daily scheduled job at 11:52 UTC (peaking at 77–92%). Peak memory is 3.08 GB out of 3.5 GB on P1v3 — S1 and P0v3 (both 1.75 GB) are insufficient. P1v3 is the correct size for this workload.

##### Total monthly saving: £534

---

### 4. Log Analytics

The Log Analytics estate costs £802/month across multiple workspaces. Four distinct areas were identified where ingestion volume and cost could be reduced.

#### A. Storage Diagnostic Logs in Non-Production Environments

Storage diagnostic data ingested per workspace in February:

- **log-cormar-integration-dev**: 68 GB (37 GB StorageFileLogs, 15 GB StorageQueueLogs, 8 GB StorageBlobLogs, 8 GB StorageTableLogs)
- **log-cormar-integration-test**: ~70 GB (similar breakdown)
- **log-cormar-integration-uat**: 31 GB
- **Total across non-prod environments: ~169 GB/month**

These logs provide minimal operational value in dev/test/UAT and are rarely queried. Disabling the StorageFileLogs, StorageQueueLogs, StorageTableLogs, and StorageBlobLogs diagnostic settings on storage accounts in these three environments removes the largest single source of unnecessary ingestion.

Estimated saving: **~£300/month** (130 GB × £2.30/GB ingestion rate).

#### B. AllMetrics in Diagnostic Settings

The AzureMetrics table across dev, test, and UAT workspaces accumulates 8.6 GB, 10.2 GB, and 7.3 GB respectively each month — approximately 26 GB total. This data is ingested when diagnostic settings include the AllMetrics option. The same metrics are available at no charge via Azure Monitor, making ingestion into Log Analytics redundant for most use cases. Removing AllMetrics from diagnostic settings across dev, test, and UAT would eliminate this overhead.

The estimated saving is approximately £60/month.

#### C. AzureDiagnostics Legacy Format

The production workspace **log-cormar-internal-prod** ingested 35.56 GB from the AzureDiagnostics table in February — 81% of that workspace's total ingestion volume. AzureDiagnostics is a legacy wide-format table that is inherently verbose and generates a larger data footprint than Resource-Specific table format. The Azure Firewall already uses Resource-Specific mode correctly. Migrating the remaining resources to Resource-Specific destination tables would reduce ingestion volume and improve query performance.

The estimated saving is £20–30/month.

#### D. Unmanaged DefaultWorkspace and Application Insights Sampling

The auto-created workspace **DefaultWorkspace-42d858f8-5e16-4cd2-bd09-2ae7ee771d11-SUK** costs £99/month, ingesting 43 GB/month (24 GB AppTraces + 19 GB AppDependencies). Six production Application Insights instances all point to this unmanaged workspace with no sampling configured:

- appi-cormar-collectionpoints
- appi-cormar-cormarapi
- appi-cormar-cormarapiwms
- appi-cormar-sapphire
- appi-cormar-planneddeliveries
- appi-cormar-poddownloader

Recommended actions:

- Redirect all six instances to a managed, named Log Analytics workspace
- Enable adaptive sampling on each instance — typically reduces telemetry volume by 50–80% with minimal impact on observability

Estimated saving from sampling alone: **£50–70/month**.

##### Total monthly saving: £430

---

### 5. Microsoft Fabric

A single Microsoft Fabric capacity, **cormarcapprod001**, runs at F8 (8 Capacity Units) at £869/month:

- Compute Pool CU: £553/month
- Spark Memory Optimized CU: £164/month
- SQL database CU: £54/month
- No pause/resume schedule found — no Automation runbooks or Logic Apps referencing this capacity; it appears to run continuously including weekends

F-series capacities support pause/resume billing — billing stops entirely when paused and resumes only when restarted. The recommendation is to implement a pause/resume schedule via Azure Automation or a Logic App.

Before setting the pause window:

- Confirm via the **Microsoft Fabric Capacity Metrics app** (available from AppSource) whether the capacity has overnight or weekend activity — scheduled refreshes, batch pipelines, or Spark jobs must be accommodated
- Assess the SQL database component separately if it serves any always-on queries

If the workload is business-hours only, pausing between 18:00–08:00 weekdays and over full weekends reduces active runtime from ~744 hours/month to ~220 hours (~70% reduction), saving **£400–500/month**. If overnight activity is present, adjust the window accordingly.

##### Total monthly saving: £450

---

### 6. Virtual WAN

The estate operates a single Virtual WAN, **cc-vwan-prod-uks-001**, with two hubs:

- **cc-vhub-prod-uks-001** (UK South) — active; hosts a Site-to-Site VPN gateway and a Point-to-Site VPN gateway
- **cc-vhub-prod-neu-001** (North Europe) — no VPN gateway attached; VirtualHubDataProcessed metric showed **zero bytes** over the full 30-day review period; costs ~£129/month without routing any traffic

Each Virtual WAN hub incurs a fixed infrastructure charge regardless of traffic. If **cc-vhub-prod-neu-001** is not being retained for a specific future purpose (e.g. planned ExpressRoute circuit or regional expansion), it should be deleted.

##### Total monthly saving: £129

---

### 7. Data Factory

Three non-production Data Factory instances are in operation:

- **cc-adf-int-dev-uks**
- **cc-adf-int-test-uks**
- **cc-adf-int-uat-uks**

All three use the Managed VNET Integration Runtime (IR), which provides private network isolation but carries a higher cost than the standard Azure IR, including a minimum billing increment of 60 minutes per pipeline run. Each factory is running its Data Ingestion pipeline actively, with over 100 runs recorded in the 30-day review period.

The Managed VNET IR is required — the connected data sources (SQL elastic pools, Service Bus namespaces, and storage accounts) are accessible only via private endpoints within their respective environment VNets. Replacing it with the standard Azure IR is not viable.

The UAT pipeline situation is materially worse than the initial review indicated. Pipeline run data for **cc-adf-int-uat-uks** was exported and analysed in full:

- **223 failed runs per day**, consistently, every day — the export captured 1,000 runs across just 4.3 days (22–26 March), with 223 runs on each full day
- **100% failure rate** — not a single successful run in the entire export
- **Root cause:** `Login failed for token-identified principal` — an Azure AD authentication failure at the first pipeline activity (`Get Key Columns`). A service principal has lost access or its credentials have expired. This is a single configuration fix
- **Trigger:** `tr_blob2`, a blob storage event trigger, fires every 2 hours as batches of ~12 files are deposited to a monitored path under `stagingdbexport/UnZipPath/`. Each file triggers a separate pipeline run, all of which immediately fail at the SQL authentication step
- **Billing impact per run:** 0.1333 hours of Managed VNET IR data movement plus 5 orchestration activity runs
- **Monthly projection:** 223 runs/day × 0.1333 hours = ~890 hours of Managed VNET IR time per month consumed by failing runs alone

**Immediate actions required:**

1. **Disable the blob trigger `tr_blob2`** on `cc-adf-int-uat-uks` — stops the issue immediately while the underlying problem is investigated
2. **Restore the service principal permissions** — the `Login failed for token-identified principal` error points to an expired or revoked Azure AD credential on the SQL connection
3. **Re-enable the trigger** once a successful test run confirms the pipeline is functioning

The Managed VNET IR configuration itself is appropriate and should not be changed.

#### Cost impact

`cc-adf-int-uat-uks` costs **£256/month** (confirmed from cost export). The pipeline failure began 22 March — the February baseline of £256/month reflects the factory running correctly. Because the trigger fires at the same frequency whether runs succeed or fail, fixing the pipeline is primarily an **operational issue** rather than a cost saving. Data is not being ingested in UAT and the environment is not functioning as intended.

---

### 8. Logic Apps

Three Standard Logic Apps are deployed on separate WS1 App Service Plans, each costing £135/month:

- **cc-aspla-int-dev-uks** (dev)
- **cc-aspla-int-test-uks** (test)
- **cc-aspla-int-uat-uks** (UAT)

Each plan hosts seven identical workflows: DMFExport, DMFImport, customerOrder, healthCheck, manufacture, stagingdb, and wms. CPU utilisation averages 1% across all three plans; memory is 67–68%, reflecting resident workflow processes.

The three separate plans are architecturally required — Standard Logic Apps support VNet integration at the plan level (one VNet per plan). Each environment has its own VNet, so each plan must remain separate. Consolidation would break connectivity.

No cost reduction recommendation is raised for this section.

---

### 9. Managed Disks — ASR Seed Disks

| Disk | SKU | Size | Status | Action |
| --- | --- | --- | --- | --- |
| asrseeddisk-coredb01-* (×3) | Premium LRS | 690 GB total | Unattached | Delete if ASR replication confirmed removed |
| cc-az-adc01-ASRReplica | Premium LRS | — | Attached | No action |

Three ASR seed disks associated with **COREDB01** are unattached:

- Prefix: `asrseeddisk-coredb01-*` (×3 disks)
- SKU: Premium LRS
- Combined capacity: 690 GB (~£90–100/month regardless of use)
- Status: unattached — appear to be orphaned from a replication setup that was reconfigured or decommissioned without removing the seed disks

For comparison, **cc-az-adc01-ASRReplica** (ADC01) is correctly attached and part of an active replication configuration.

Before deleting, confirm:

- The current ASR replication status for COREDB01
- No active replication job is still referencing these disks

If replication has been removed or reconfigured, the three seed disks can be safely deleted.

##### Total monthly saving: £90

---

### 10. Application Gateway

**cc-appgw-nprd-uks-001** is deployed in a non-production subscription at the WAF_v2 tier with autoscaling enabled:

- Current cost: £307/month (WAF_v2 base cost: £233/month + capacity units)
- All three backend pools populated — apim-gateway, apim-management, apim-portal — confirming the gateway is actively routing traffic
- Standard_v2 provides the same core routing functionality at a significantly lower base rate

The WAF capability in WAF_v2 protects against web exploits such as SQL injection and cross-site scripting. Non-production environments do not typically face the same threat profile as production and are generally not subject to WAF compliance requirements.

Recommendation: downgrade to Standard_v2, subject to confirming no internal policy or compliance requirement applies to this gateway.

##### Total monthly saving: £125

---

### 11. Defender for Cloud

Defender for Cloud is enabled across three production subscriptions — **42d858f8**, **6a097093**, and **9f2c3f43** — with an identical plan set on each, consistent with a policy-driven deployment.

**Plans enabled with no matching resources:**

- **Containers** — no AKS clusters found across any of the three subscriptions
- **CosmosDbs** — no Cosmos DB instances found
- **OpenSourceRelationalDatabases** — no PostgreSQL or MySQL databases found

**Plans correctly in use — retain:**

- **StorageAccounts (DefenderForStorageV2)** — storage accounts are present and active
- **VirtualMachines P2** with AgentlessVmScanning — appropriate for production VMs

Defender does not charge for resource types that do not exist, but having these plans enabled means billing would begin automatically if a matching resource were ever deployed without an explicit opt-in decision.

**Recommendation:** Disable Containers, CosmosDbs, and OpenSourceRelationalDatabases on all three production subscriptions. This removes unnecessary coverage, simplifies the security posture, and prevents unintended billing from future resource deployments.

##### Total monthly saving: £40

---

### 12. Backup

| Vault | Redundancy | Daily Retention | Monthly Cost | Action |
| --- | --- | --- | --- | --- |
| cc-rsv-corpvmbackup-prod-neu-001 | GRS | 180 days | £69 | Review — reduce to 30–90 days if no compliance requirement |
| cc-rsv-corpvmbackup-prod-uks-001 (equivalent) | GRS | 30 days | £48 | No action |
| CC-AZ-MIG* vaults (×3) | — | — | £0 | Confirm empty, then delete |

Nine Recovery Services Vaults are in operation, all configured with GeoRedundant (GRS) storage and CrossRegionRestore enabled on active vaults.

**Standard configuration (appropriate — no action):**

- Most vaults apply a 30-day daily retention period, which is appropriate for virtual machine workloads
- CrossRegionRestore is enabled on active vaults — consistent with GRS redundancy

**Exceptions requiring review:**

- Policy **cc-bkpol-azvm-daily-neu-001** on vault **cc-rsv-corpvmbackup-prod-neu-001** uses a **180-day daily retention period** — six times the standard retention elsewhere
- No monthly or yearly retention schedules are configured alongside this, which would normally accompany a formal compliance requirement
- This extended retention is the primary reason this vault costs £69/month versus £48/month for the equivalent UK South vault

**Migration vaults — three vaults following the CC-AZ-MIG* pattern:**

- Located in the migration resource group with no associated costs in the February export — likely empty
- Must be confirmed as containing no protected items before deletion

**Recommendations:**

1. Review whether the 180-day retention is tied to a specific business or compliance requirement — if not, reduce to 30–90 days to align with the rest of the estate
2. Confirm the CC-AZ-MIG* vaults contain no protected items, then delete them

##### Total monthly saving: £25

---

### 13. Bastion

| Instance | SKU | Monthly Cost | Action |
| --- | --- | --- | --- |
| cc-bastion-prod-uks-001 | Standard | £150 | Downgrade to Basic if native client / tunnelling not used |
| (4 × Developer SKU instances) | Developer | £0 | No action |

The estate has five Bastion instances:

- **cc-bastion-prod-uks-001** — Standard SKU, £150/month
- **Four Developer SKU instances** — no charge

**Standard vs Basic feature comparison for cc-bastion-prod-uks-001:**

- Standard provides: native client support, tunnelling, shareable links, IP-based connection, multiple concurrent sessions
- Basic provides: browser-based RDP and SSH access only (~£115/month)

**Recommendation:** If tunnelling and shareable links are not actively used by the team, downgrade to Basic SKU. The change is low-effort and fully reversible — Standard features can be re-enabled at any time if required.

##### Total monthly saving: £35

---

### 14. Orphaned Public IP Addresses

| Resource | Status | Action |
| --- | --- | --- |
| pip-apim-ecommerce-prod | Unassociated | Delete if no planned use |
| pip-vgw-prod | Unassociated | Delete if no planned use |
| vnet-corp-prod-ip | Unassociated | Delete if no planned use |

Three static public IP addresses are unassociated with any running resource:

- **pip-apim-ecommerce-prod** — unattached
- **pip-vgw-prod** — unattached
- **vnet-corp-prod-ip** — unattached

Static public IPs in Azure accrue a charge regardless of whether they are attached to a resource. These represent avoidable spend with no operational benefit.

**Recommendation:** Confirm none of the three are reserved for a planned deployment, then delete them. In most cases a replacement static IP can be allocated if a fixed address is later needed.

##### Total monthly saving: £31

---

### 15. Virtual Machines

Cormar Carpets operates 14 virtual machines across multiple subscriptions.

| VM | Size | vCPU | RAM | CPU Avg | Available Mem | Auto-shutdown | Action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CC-ADO-AGENT | E2s_v5 | 2 | 16 GB | ~5–30% | Adequate | Yes | No action |
| CC-AZ-COREDB01 | E4s_v5 | 4 | 32 GB | ~5–30% | Adequate | Yes | No action |
| CC-AZ-ADC01 | D2s_v3 | 2 | 8 GB | ~5–30% | Adequate | Yes | No action |
| CC-AZ-DC01 | F4s_v2 | 4 | 8 GB | ~5–30% | Adequate | Yes | No action |
| CC-AZ-DC02 | F4s_v2 | 4 | 8 GB | ~5–30% | Adequate | Yes | No action |
| CC-AZ-LM01 | D4ds_v4 | 4 | 16 GB | ~5–30% | Adequate | Yes | No action |
| CC-AZ-LM02 | D4ds_v4 | 4 | 16 GB | ~5–30% | Adequate | Yes | No action |
| CC-DEV1-1 | D13_v2 | 8 | 56 GB | 2.7–6.4% | 42–48 GB free | Yes | Right-size to D8s_v3 |
| CC-DEV2-1 | D13_v2 | 8 | 56 GB | — | — | Yes | Right-size to D8s_v3 (deallocated at review) |
| CC-DEV3-1 | D13_v2 | 8 | 56 GB | 2.7–6.4% | 42–48 GB free | Yes | Right-size to D8s_v3 |
| CC-DEVINT-1 | D13_v2 | 8 | 56 GB | 2.7–6.4% | 42–48 GB free | Yes | Right-size to D8s_v3 |
| CC-HSOTEST-1 | D13_v2 | 8 | 56 GB | 2.7–6.4% | 42–48 GB free | Yes | Right-size to D8s_v3 |
| CC-PROTO-1 | D13_v2 | 8 | 56 GB | 2.7–6.4% | 42–48 GB free | Yes | Right-size to D8s_v3 |
| CC-SANDBOX-1 | D13_v2 | 8 | 56 GB | 2.7–6.4% | 42–48 GB free | Yes | Right-size to D8s_v3 (deallocated at review) |

**Corporate / shared services VMs (no action):**

- CC-ADO-AGENT (E2s_v5), CC-AZ-COREDB01 (E4s_v5), CC-AZ-ADC01 (D2s_v3), CC-AZ-DC01 and DC02 (F4s_v2), CC-AZ-LM01 and LM02 (D4ds_v4)
- CPU utilisation in the 5–30% range; appropriate memory headroom for each role
- Not right-sizing candidates at this time

**Sandbox developer VMs (right-sizing opportunity):**

- All seven provisioned at Standard_D13_v2 (8 vCPU, 56 GB RAM): CC-DEV1-1, CC-DEV2-1, CC-DEV3-1, CC-DEVINT-1, CC-HSOTEST-1, CC-PROTO-1, CC-SANDBOX-1
- Auto-shutdown schedules configured on all seven
- CC-DEV2-1 and CC-SANDBOX-1 were deallocated at the time of review
- 30-day metrics for actively running VMs: average CPU 2.7–6.4%; available memory 42–48 GB — only 8–14 GB of 56 GB provisioned capacity is consumed
- The D13_v2 is a memory-intensive instance designed for workloads requiring close to 56 GB RAM; no sandbox workload approaches that ceiling

**Recommendation:** Right-size all seven sandbox VMs from Standard_D13_v2 to **Standard_D8s_v3** (8 vCPU, 32 GB RAM):

- Same core count; removes 24 GB of unused RAM per VM
- D8s_v3 includes premium storage support, matching existing disk configuration
- D13_v2 costs ~£0.60/hour vs £0.31/hour for D8s_v3
- Estimated saving across five actively running VMs: £250–300/month
- Apply the right-sizing action to CC-DEV2-1 and CC-SANDBOX-1 when next started

##### Total monthly saving: £275

---

## Summary Table

| Item | Potential Monthly Cost Saving | Effort to Implement |
| --- | --- | --- |
| SQL Elastic Pools — downgrade 9 idle non-prod pools to Basic; right-size prod pool | £519 | Half Day |
| Azure Firewall — downgrade Premium to Standard tier | £310 | Half Day |
| App Service Plans — downgrade cc-aspfacloud-int-test-uks B3→B1 | £28 | 1 Hour |
| App Service Plans — downgrade 3 non-prod P0v3 plans to B1 | £113 | 1 Hour |
| App Service Plans — downgrade cc-asp-b2b-dev P1v3→B2 | £78 | 1 Hour |
| App Service Plans — downgrade plan-cormar-internal-prod P2v3→P1v3 (monitor memory) | £180 | 1 Hour |
| App Service Plans — downgrade plan-cormar-sapphire-prod S3→S2 | £135 | 1 Hour |
| Log Analytics — disable storage diagnostic logs (dev/test/uat) | £300 | Half Day |
| Log Analytics — remove AllMetrics from diagnostic settings | £60 | 2 Hours |
| Log Analytics — migrate AzureDiagnostics to Resource-Specific | £25 | 2 Hours |
| Log Analytics — redirect App Insights to managed workspace with sampling | £60 | 2 Hours |
| Microsoft Fabric — implement pause/resume schedule | £450 | 2 Hours |
| Virtual WAN — delete unused North Europe hub | £129 | 1 Hour |
| Data Factory — fix UAT service principal; restore pipeline operation | Operational fix | Half Day |
| Managed Disks — delete orphaned ASR seed disks (COREDB01) | £90 | 1 Hour |
| Application Gateway — downgrade non-prod WAF_v2 to Standard_v2 | £125 | 2 Hours |
| Defender for Cloud — disable plans with no matching resources | £40 | 1 Hour |
| Backup — reduce 180-day retention; delete migration vaults | £25 | 1 Hour |
| Bastion — downgrade Standard to Basic SKU | £35 | Negligible |
| Orphaned Public IP Addresses — delete 3 unused IPs | £31 | Negligible |
| Virtual Machines — right-size sandbox D13_v2 fleet to D8s_v3 | £275 | Half Day |
| **Total** | **£3,008** | **~5 Days** |

---

## Further Review Items

The following cost categories were identified during the review but not analysed in depth. They represent approximately **£3,450/month** of estate spend and are flagged here for manual follow-up.

| Item | Monthly Spend | Notes |
| --- | --- | --- |
| Private Endpoints | £1,670 | 329 endpoints at ~£5.17/month each. Primarily architectural necessities, but orphaned endpoints from decommissioned resources are a common source of waste. Recommend auditing for endpoints with no associated resource. |
| Azure DevOps (`cormarhso`) | £523 | Organisation-level billing in the corp subscription. Common areas to review: unused parallel CI/CD jobs, Basic+Test Plans licences assigned to users who don't require test features, and artifact storage retention. |
| Storage Accounts | £477 | Spread across 12 subscriptions. Largest individual accounts: ASR cache (£70), Trade Portal (£66), Internal app (£54), Integration dev/test (~£45 each). Review access tier (Hot vs Cool vs Archive), redundancy tier (GRS vs LRS), and lifecycle management policies. |
| Azure Front Door | £274 | Single resource: `afd-connectivity-prod-uksouth-001`. Review Standard vs Premium tier and whether WAF policy is active and required. |
| Azure Reservations | £208 | Five reservation orders in the corp subscription (amortised cost). Not a saving opportunity, but expiry dates should be confirmed to ensure renewals are planned. |
| Synapse Analytics | £136 | Spark Pool `ccsynspdnadev` in the nonprod subscription costs £126/month in a dev environment. Confirm whether auto-pause is configured — if not, enabling it would reduce this cost materially when the pool is idle. |
| Managed DevOps Pools | £95 | `cc-mdop-prod-uks-001` in the prod subscription. Review agent count, scale-down configuration, and whether usage justifies the standing cost. |
| API Management | £68 | Two instances: `apim-cormar-ecommerce-prod-uks-001` (dmz, £34) and `cc-apim-nprd-uks-001` (nonprod, £34). Confirm tier and whether the nonprod instance needs to run continuously. |
