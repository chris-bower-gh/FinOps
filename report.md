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

#### Non-production pools — idle compute

Utilisation metrics across the 30-day review period reveal that 10 non-production pools recorded 0% average DTU consumption — not low utilisation, but zero recorded activity throughout the entire measurement window:

- `cc-sqlep-b2b-dev-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-b2b-uat-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-b2c-uat-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-bhm-dev-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-bhm-uat-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-cstmr-dev-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-cstmr-uat-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-hm-dev-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-hm-uat-uks-001` (50 DTU Standard) — 0% avg, 0% max
- `cc-sqlep-staging-dev-uks` (50 DTU Basic) — 0% avg, 0% max

A further four non-prod pools show minimal but non-zero activity: `cc-sqlep-bhm-test-uks-001` spikes to 100% max but averages 0%; `cc-sqlep-hm-test-uks-001` peaks at 12%; `cc-sqlep-staging-test-uks` peaks at 53%; and `cc-sqlep-b2b-test-uks-001` (100 DTU Standard) peaks at 58.6% with a 0.1% average — suggesting infrequent, short-duration burst activity rather than sustained load. All ten completely idle pools are retained for future use, but each is billing at 50 DTU Standard regardless of activity.

Each pool exists within its own environment lane as part of the deliberate network segregation across the estate — dev, test, and UAT pools are not candidates for cross-environment consolidation and should be treated independently.

#### Production pool — over-provisioned

`sqlep-cormar-common-dmz-prod-uks-001` is a production pool configured at 400 DTU Standard, costing approximately £290/month. Seven days of 1-minute granularity metrics (19–26 March 2026) were analysed to understand its true consumption profile.

The pool is idle 59% of the time. P95 consumption is 20 eDTU, P99 is 32 eDTU, and business-hours P99 is 44 eDTU. The 30-day metrics used in the initial review showed a maximum of 6% (approximately 24 DTU) because the coarser aggregation interval averaged out brief spikes that the 1-minute data captures directly.

Every one of the 27 minutes across the 7-day window where the pool reached 400 eDTU occurred in an identical pattern: 06:16–06:20 UTC, every single day including weekends. This is a scheduled batch job — not organic workload — and it is the sole justification for the current pool size. Outside of this 4–5 minute daily window, no other event comes close to saturating the pool; the highest daytime organic spike observed was a single 1-minute burst of 260 eDTU.

The recommendation for the nine idle 50 DTU Standard pools is to downgrade them to the Basic tier while they remain inactive. Basic pools carry a significantly lower per-eDTU cost than Standard, and the change is fully reversible — upgrading back to Standard is supported with a brief connection interruption (typically under 30 seconds) and no data loss, and should be performed at the point each environment is activated for use.

Before downgrading, the following should be confirmed for each pool: (1) no individual database within the pool contains more than 2 GB of used data (the Basic per-database storage ceiling); (2) no databases contain columnstore indexes, which are not supported in the Basic tier. For these idle, zero-activity pools both conditions are unlikely to be an issue, but should be verified before proceeding.

One functional constraint to be aware of: the Basic tier caps each database at a fixed maximum of 5 eDTUs, regardless of pool size. This is sufficient for most dev and UAT workloads, but if any application targeting these environments requires per-database burst headroom beyond 5 eDTUs — for example during load tests or bulk data imports — it will be throttled. The team activating each environment should confirm this is acceptable before the pool is downgraded rather than upgraded.

For `sqlep-cormar-common-dmz-prod-uks-001`, the recommendation is a two-stage approach. First, right-size immediately from 400 DTU to 100 DTU Standard — this comfortably covers all business-hours organic load (P99 = 44 eDTU) and reduces the monthly cost from approximately £290 to £75, a saving of £215/month. The 06:16 batch job will throttle to 100 DTU during its 4–5 minute window rather than consuming the full 400 DTU; for a scheduled background job this is unlikely to be operationally significant, but should be confirmed with the team responsible. Second, the 06:16 job itself should be investigated — its precise 4-minute burst profile and 7-day-a-week schedule suggest an automated maintenance task such as an index rebuild or ETL process. If it can be rate-limited or confirmed as tolerant of the 100 DTU ceiling, the pool could be reduced further to 50 DTU Standard, eliminating any residual saturation. `sqlep-cormar-common-prod-uks-001` (4 vCore GeneralPurpose) was also reviewed using 7-day 1-minute granularity CPU metrics. Although average CPU is 4.8% and the pool is idle more than 80% of the time, it hosts multiple recurring scheduled jobs that fire daily including weekends — most notably a job at 07:02–07:08 UTC which consistently peaks at 75–89% CPU. On a 2 vCore pool (the minimum GeneralPurpose size), this job would demand 150–178% of capacity, causing hard throttling every morning. P99 demand across the 7-day window is 2.16 vCores, confirming that a 2 vCore pool would be insufficient. The current 4 vCore provisioning is appropriate and no right-sizing action is recommended for this pool.

##### Total monthly saving: £519

---

### 2. Azure Firewall

The estate uses a single Azure Firewall, **cc-afw-prod-uks-001**, deployed at the Premium tier as a Secured Virtual Hub integrated into the Virtual WAN. The Premium deployment alone costs £906/month, with an additional £67/month in data processing charges, bringing the total to approximately £1,021/month. Diagnostic settings are correctly configured — Resource-Specific table mode is in use, FatFlow and FlowTrace logging are appropriately disabled, and logs are directed to the workspace **cc-log-azfwstructuredlogs-prod-uks-001**.

The case for Premium tier rests on three features not available in the Standard tier: IDPS (Intrusion Detection and Prevention System), TLS inspection, and URL filtering. Of these, IDPS was found to be disabled in the diagnostic settings review, which calls into question whether the Premium-specific capabilities are actively in use. TLS inspection and URL filtering enablement could not be confirmed as active during the review period. If these features are not in use and there are no firm plans to enable them, the Premium tier is not providing the value that justifies its cost differential over Standard.

A Standard Secured Virtual Hub Firewall costs approximately £580/month, representing a saving of roughly £320/month. Before making this change, the Cormar IT team should confirm whether IDPS, TLS inspection, or URL filtering are actively enforced or are part of a near-term security roadmap. If they are not, downgrading to Standard tier should be considered.

##### Total monthly saving: £310

---

### 3. App Service Plans

Across 36 App Service Plans, the total monthly spend is £1,802, with non-production plans accounting for approximately £1,100 of that figure. A full inventory review identified several plans operating above Basic tier. Seven-day 1-minute CPU and memory metrics were analysed for each before any recommendation was made.

#### Non-production plans — oversized SKUs

**cc-aspfacloud-int-test-uks** runs on B3 with average CPU of 6.4% and a maximum of 71%. The equivalent dev environment, **cc-aspfacloud-int-dev-uks**, runs on B1 with similar workloads at an average of 48% — well within B1 capability. Recommendation: downgrade to B1.

All four Premium V3 non-production plans were confirmed as running manual scale with no deployment slots — there is no feature-gate reason to remain on Premium. Metrics confirm the following:

**`cc-asp-b2bv1-test-uks-001`** (P0v3, Windows, test, 2 apps): P0v3 is a burstable 0.25 vCPU tier. Memory peak is 1,541 MB — within the 1.75 GB B1 ceiling. CPU spikes that currently saturate the burstable 0.25 vCPU core translate to approximately 25% on B1's full vCPU. **Downgrade to B1 is supported.**

**`cc-asp-hm-test-uks-001`** (P0v3, Linux, test, 1 app): Memory peak is 896 MB — well within B1. CPU never exceeded 38% across the full 7-day window. **Downgrade to B1 is supported.**

**`cc-aspfabhm-int-test-uks`** (P0v3, Linux, test, 2 apps): Memory peak is 1,147 MB — within B1. A single 53% CPU spike lasting one minute was the worst case observed; on B1's full vCPU this translates to ~13%. **Downgrade to B1 is supported.**

**`cc-asp-b2b-dev-uks-001`** (P1v3, Windows, dev, 2 apps): Memory peak is 1.435 GB — fits within B1's 1.75 GB with 315 MB headroom. However, a recurring daily scheduled job fires at approximately 10:57–10:58 UTC and spikes CPU to 80–91% of the current 2 vCPU capacity every day. On a single-vCPU B1 this would translate to near-100% utilisation for 1–2 minutes each day, risking request queuing. **Downgrade to B2 is recommended** (2 vCPU, 3.5 GB RAM — same core count as P1v3, retaining the ability to absorb the spike, at a significantly lower cost than P1v3). B1 is not recommended without first identifying and resolving the 10:57 scheduled task.

#### Production plans

**`plan-cormar-internal-prod-uks-001`** (P2v3, Windows, 7 apps): Memory is the dominant consideration. P99 memory consumption is 2.88 GB and the observed peak is 3.12 GB — against the P2v3's 8 GB allocation, this is 39% utilisation. However, the next tier down is P1v3 at 3.5 GB, which would leave only 380 MB headroom at the observed peak (89% utilised). CPU is not a concern — P99 is 27% of 2 vCPU and all spikes are 1–2 minute transients. **A move from P2v3 to P1v3 is conditionally recommended**, with a memory alert set at 80% (2.8 GB) immediately after migration and close monitoring for four weeks. If any of the 7 hosted applications is expected to grow in memory usage, or if additional applications are deployed to this plan, the move should not proceed.

**`plan-cormar-sapphire-prod-uks-001`** (S3, Windows, 1 app): S3 provides 4 vCPU and 7 GB RAM for a single application. Memory peak across 7 days was 3.15 GB — this rules out S1 and B1 (both 1.75 GB) but fits within S2's 3.5 GB, leaving approximately 350 MB headroom at the observed maximum. CPU shows a confirmed daily scheduled job firing at 10:45–10:46 UTC every day including weekends, reaching 97–100% of the current 4 vCPU capacity for 1–2 minutes. On S2 (2 vCPU) this burst would take 2–4 minutes. All other CPU usage is negligible (P99 outside the spike window is well under 25%). **Downgrade from S3 to S2 is recommended**, subject to confirming that the 10:45 scheduled job is not latency-sensitive and can tolerate a longer burst window.

**`plan-cormar-collectionpoints-prod-uks-001`** (S2, Windows, 7 apps): This plan is already operating at its minimum viable size and presents no right-sizing opportunity. CPU P99 is 92% of 2 vCPU, with 100% saturation events observed. Memory P99 is 2.8 GB and the peak observed was 3.255 GB — leaving only 245 MB headroom against the 3.5 GB S2 ceiling. The recurring :01 and :31 minute-of-hour CPU pattern (mean 60% and 56% respectively at those minutes) suggests scheduled jobs firing on every hour and half-hour and warrants investigation, though this is a performance concern rather than a cost one. No downgrade is recommended; any further load growth on this plan would indicate a need to scale up rather than down.

#### plan-cormar-tradeportal-prod-uks-001 — no right-sizing opportunity

Seven days of 1-minute CPU metrics were analysed. Average CPU is 7.9% but spikes to 90–100% are frequent during business hours, driven by a confirmed daily scheduled job at 11:52 UTC (every day including weekends, peaking at 77–92%). Peak memory is 3.08 GB out of the 3.5 GB available on P1v3 — S1 and P0v3 (both 1.75 GB) are insufficient. P1v3 is the correct size for this workload.

##### Total monthly saving: £534

---

### 4. Log Analytics

The Log Analytics estate costs £802/month across multiple workspaces, and the analysis identified four distinct areas where ingestion volume and cost could be reduced. These are addressed in turn below.

#### A. Storage Diagnostic Logs in Non-Production Environments

The integration dev workspace, **log-cormar-integration-dev**, ingested 68 GB of storage diagnostic data in February alone — comprising 37 GB of StorageFileLogs, 15 GB of StorageQueueLogs, 8 GB of StorageBlobLogs, and 8 GB of StorageTableLogs. The integration test workspace, **log-cormar-integration-test**, shows a similar pattern at approximately 70 GB, and the UAT workspace, **log-cormar-integration-uat**, contributed a further 31 GB. Across all three non-production environments, this amounts to approximately 169 GB of storage diagnostic data per month. Storage diagnostic logs in dev, test, and UAT environments provide minimal operational value — they are not typically used for active troubleshooting in these tiers, and the data is rarely queried. Disabling the StorageFileLogs, StorageQueueLogs, StorageTableLogs, and StorageBlobLogs diagnostic settings on storage accounts in these environments would remove the largest single source of unnecessary ingestion in the estate.

Saving from this change alone is approximately £300/month based on 130 GB at the standard ingestion rate of £2.30/GB.

#### B. AllMetrics in Diagnostic Settings

The AzureMetrics table across dev, test, and UAT workspaces is accumulating 8.6 GB, 10.2 GB, and 7.3 GB respectively each month — totalling approximately 26 GB. This data is ingested when diagnostic settings include the AllMetrics option. The same metrics are available at no charge via Azure Monitor and the Metrics blade, making their ingestion into Log Analytics redundant for most use cases. Removing AllMetrics from diagnostic settings across the dev, test, and UAT environments would eliminate this overhead.

The estimated saving from removing AllMetrics is approximately £60/month.

#### C. AzureDiagnostics Legacy Format

The production workspace **log-cormar-internal-prod** ingested 35.56 GB from the AzureDiagnostics table in February, representing 81% of that workspace's total ingestion volume. AzureDiagnostics is a legacy, wide-format table that aggregates diagnostic data from multiple resource types into a single schema; it is inherently verbose and generates a larger data footprint than the Resource-Specific table format. The Azure Firewall in this estate already uses Resource-Specific mode correctly, demonstrating that the approach is established and understood. Migrating the remaining resources that currently send to AzureDiagnostics over to Resource-Specific destination tables would reduce ingestion volume and associated cost.

The estimated saving from this migration is £20–30/month, with the additional benefit of improved query performance and schema clarity.

#### D. Unmanaged DefaultWorkspace and Application Insights Sampling

The auto-created workspace **DefaultWorkspace-42d858f8-5e16-4cd2-bd09-2ae7ee771d11-SUK** is costing £99/month and is ingesting 43 GB per month — comprising 24 GB of AppTraces and 19 GB of AppDependencies. This data originates from multiple production Application Insights instances: **appi-cormar-collectionpoints**, **appi-cormar-cormarapi**, **appi-cormar-cormarapiwms**, **appi-cormar-sapphire**, **appi-cormar-planneddeliveries**, and **appi-cormar-poddownloader**, all of which are pointing to this unmanaged, auto-generated workspace. None of these instances have sampling configured — all telemetry is ingested at 100%. Adaptive sampling, which is a built-in Application Insights feature, typically reduces telemetry volume by 50–80% with minimal impact on observability, as it preserves statistical representation of request patterns and exceptions while discarding a proportion of routine traces.

The recommendation is to redirect these Application Insights instances to a managed, named Log Analytics workspace, and to enable adaptive sampling on each instance. The estimated saving from sampling alone is £50–70/month.

##### Total monthly saving: £430

---

### 5. Microsoft Fabric

A single Microsoft Fabric capacity, **cormarcapprod001**, runs at the F8 SKU (8 Capacity Units) at a cost of £869/month. The capacity carries an active workload: the cost breakdown shows £553/month for Compute Pool CU, £164/month for Spark Memory Optimized CU, and £54/month for SQL database CU. F-series Fabric capacities support a pause feature whereby billing stops entirely when the capacity is in a paused state — the meter ceases the moment the capacity is paused and resumes only when it is restarted. No pause schedule was identified during the review: there are no Azure Automation runbooks or Logic Apps referencing **cormarcapprod001**, and the capacity appears to be running continuously at all hours including weekends.

The recommendation is to implement a pause/resume schedule using Azure Automation or a Logic App. Before setting the pause window, the Cormar team should confirm via the Microsoft Fabric Capacity Metrics app (available from AppSource) whether the capacity has any overnight or weekend activity — scheduled refreshes, batch pipelines, or background jobs would need to be accommodated in the schedule. If the workload is genuinely business-hours only, pausing between 18:00 and 08:00 on weekdays and over full weekends would reduce active runtime from approximately 744 hours per month to around 220 hours — a reduction of approximately 70%. Applying that reduction to the compute cost produces a saving in the range of £400–500/month. If overnight activity is present, the pause window should be adjusted accordingly, which would reduce the saving proportionally. The SQL database component should also be assessed separately if it serves any always-on queries.

##### Total monthly saving: £450

---

### 6. Virtual WAN

The estate operates a single Virtual WAN, **cc-vwan-prod-uks-001**, with two hubs. The UK South hub, **cc-vhub-prod-uks-001**, hosts an active Site-to-Site VPN gateway (**cc-vgw-prod-uks-001**) and a Point-to-Site VPN gateway, and is clearly in active use. The North Europe hub, **cc-vhub-prod-neu-001**, has no VPN gateway attached. Reviewing the VirtualHubDataProcessed metric for this hub over the full 30-day review period showed zero bytes of data processed — the hub is consuming infrastructure charges of approximately £129/month without routing any traffic.

Each Virtual WAN hub incurs a fixed infrastructure charge regardless of whether traffic flows through it. Where a hub is genuinely idle and has no planned purpose, retaining it represents avoidable spend. The Cormar IT team should confirm whether **cc-vhub-prod-neu-001** is being retained for a specific future purpose — for example, a planned ExpressRoute circuit or a regional expansion — and if no such purpose exists, the hub should be deleted.

##### Total monthly saving: £129

---

### 7. Data Factory

Three non-production Data Factory instances are in operation: **cc-adf-int-dev-uks**, **cc-adf-int-test-uks**, and **cc-adf-int-uat-uks**. All three use the Managed VNET Integration Runtime — a configuration that provides private network isolation for data movement but carries a higher cost than the standard Azure Integration Runtime, including a minimum billing increment of 60 minutes per pipeline run regardless of actual execution time. Each of the three factories is running its Data Ingestion pipeline actively, with over 100 runs recorded in the 30-day review period.

The Managed VNET IR is present in all three non-production instances because the data sources they connect to — SQL elastic pools, Service Bus namespaces, and storage accounts — are accessible only via private endpoints within their respective environment VNets. Replacing the Managed VNET IR with the standard Azure IR would remove private network connectivity and is not a viable option while those data sources remain private-endpoint-only.

The UAT pipeline situation is materially worse than the initial review indicated. Pipeline run data for **cc-adf-int-uat-uks** was exported and analysed in full. The findings are as follows:

- **223 failed runs per day**, consistently, every day — the export captured 1,000 runs (the portal export cap) across just 4.3 days (22–26 March), with 223 runs recorded on each full day
- **100% failure rate** — not a single successful run in the entire export
- **Root cause:** `Login failed for token-identified principal` — an Azure AD authentication failure at the first pipeline activity (`Get Key Columns`). A service principal has lost access or its credentials have expired. This is a single configuration fix
- **Trigger:** `tr_blob2`, a blob storage event trigger, fires every 2 hours as batches of approximately 12 files are deposited to a monitored path under `stagingdbexport/UnZipPath/`. Each file triggers a separate pipeline run, all of which immediately fail at the SQL authentication step
- **Billing impact per run:** 0.1333 hours of Managed VNET IR data movement plus 5 orchestration activity runs — confirmed from the pipeline run consumption detail
- **Monthly projection:** 223 runs/day × 0.1333 hours = approximately 890 hours of Managed VNET IR time per month consumed by failing runs alone

The original estimate of £175/month was based on the assumption of occasional failures. At 223 failures per day the actual cost attributable to this broken pipeline represents a substantial portion of the £688/month total ADF spend. The exact figure depends on the per-DIU-hour rate applied by Azure, but the scale of waste is clear.

**Immediate actions required:**

1. **Disable the blob trigger `tr_blob2`** on `cc-adf-int-uat-uks` — this stops the bleeding immediately while the underlying issue is investigated
2. **Restore the service principal permissions** — the `Login failed for token-identified principal` error points to an expired or revoked Azure AD credential on the SQL connection. Fixing this resolves the root cause
3. **Re-enable the trigger** once a successful test run confirms the pipeline is functioning

The Managed VNET IR configuration itself is appropriate and should not be changed.

#### Cost impact

`cc-adf-int-uat-uks` costs **£256/month** (confirmed from cost export). The pipeline failure began 22 March — the February baseline of £256/month reflects the factory running correctly. Because the trigger fires at the same frequency whether runs succeed or fail, fixing the pipeline is primarily an **operational issue** rather than a cost saving. Data is not being ingested in UAT and the environment is not functioning as intended. The cost of failed runs is broadly comparable to successful runs; resolving this restores correct operation rather than reducing spend materially.

---

### 8. Logic Apps

Three Standard Logic Apps are deployed, each hosted on its own WS1 App Service Plan: **cc-aspla-int-dev-uks**, **cc-aspla-int-test-uks**, and **cc-aspla-int-uat-uks**, each costing £135/month. Each plan hosts seven identical workflows — DMFExport, DMFImport, customerOrder, healthCheck, manufacture, stagingdb, and wms — mirroring the same set across dev, test, and UAT tiers. CPU utilisation across all three plans averages 1%, indicating that the underlying compute is almost entirely idle from a processing perspective. Memory utilisation is in the 67–68% range, reflecting that the workflow processes are resident in memory, but the low CPU figure confirms that active execution is minimal.

The three separate plans are consistent with the broader network topology: each environment has its own VNet, and Standard Logic Apps plans support VNet integration at the plan level — a single plan can only integrate with one VNet. The dev Logic Apps connect to dev VNet resources, the test Logic Apps to test VNet resources, and so on. Consolidating plans across environments would break this connectivity and is not appropriate.

No cost reduction recommendation is raised for this section. The separate plans reflect a deliberate architectural choice and the cost is proportionate given the private network isolation they provide.

---

### 9. Managed Disks — ASR Seed Disks

Three unattached managed disks were identified in the resource inventory: **asrseeddisk-coredb01-*** (three disks sharing this prefix), all provisioned as Premium_LRS with a combined capacity of 690 GB. These are Azure Site Recovery seed disks associated with the server **COREDB01** and are not currently attached to any virtual machine. For comparison, the equivalent ASR replica disk for ADC01 — **cc-az-adc01-ASRReplica** — is correctly attached and forms part of an active replication configuration. The COREDB01 seed disks appear to be orphaned, most likely from a replication setup that was reconfigured or decommissioned without the associated seed disks being removed. Premium_LRS storage at 690 GB costs approximately £90–100/month regardless of whether the disks are in use.

Before deleting these disks, the Cormar IT team should confirm the current ASR replication status for COREDB01 — if an active replication job is still referencing these disks, deletion would affect that protection. If replication has been removed or reconfigured to use different resources, the three seed disks can be safely deleted.

##### Total monthly saving: £90

---

### 10. Application Gateway

A single Application Gateway, **cc-appgw-nprd-uks-001**, is deployed in a non-production subscription at the WAF_v2 tier with autoscaling enabled, at a cost of £307/month. The WAF_v2 tier carries a fixed base cost of £233/month before any capacity unit charges are applied; the Standard_v2 tier offers the same core gateway functionality at a significantly lower base rate. The three backend pools — apim-gateway, apim-management, and apim-portal — are all populated, confirming that the gateway is actively routing traffic to the non-production APIM instance and is not simply an idle resource.

The WAF (Web Application Firewall) capability included in the WAF_v2 tier provides protection against common web exploits such as SQL injection and cross-site scripting. While this is a valuable control for production workloads, non-production environments do not typically face the same threat profile and are generally not subject to compliance requirements mandating WAF protection. Downgrading **cc-appgw-nprd-uks-001** to Standard_v2 would retain all routing functionality while removing the WAF layer and its associated cost premium. This change should only be made once the team has confirmed that no compliance or internal policy requirement applies to this gateway.

##### Total monthly saving: £125

---

### 11. Defender for Cloud

Defender for Cloud is enabled across three production subscriptions — 42d858f8, 6a097093, and 9f2c3f43 — with an identical set of Defender plans active on each, consistent with a policy-driven deployment. The plans enabled include **Containers**, **CosmosDbs**, and **OpenSourceRelationalDatabases**. A review of the resource inventory across these subscriptions found no AKS clusters, no Cosmos DB instances, and no PostgreSQL or MySQL databases. Defender plans do not charge for resource types that do not exist in the subscription at the time of billing — however, having these plans enabled means that if a resource of the relevant type is ever deployed, even inadvertently, Defender billing for that plan would begin without any explicit opt-in decision.

The **StorageAccounts (DefenderForStorageV2)** plan is correctly enabled and represents a genuine, appropriate security control that should be retained. **VirtualMachines P2** with AgentlessVmScanning is similarly appropriate for production workloads. The recommendation is to disable the Containers, CosmosDbs, and OpenSourceRelationalDatabases plans on all three production subscriptions. While the immediate direct saving is modest — these plans only charge when matching resources exist — removing them reduces unnecessary coverage, simplifies the security posture, and eliminates the risk of unintended billing if resources of these types are created in future.

##### Total monthly saving: £40

---

### 12. Backup

Nine Recovery Services Vaults are in operation across the estate, all configured with GeoRedundant (GRS) storage and CrossRegionRestore enabled on active vaults. The majority of backup policies apply a 30-day daily retention period, which is appropriate for virtual machine backup workloads. One exception stands out: the policy **cc-bkpol-azvm-daily-neu-001**, applied to the North Europe vault **cc-rsv-corpvmbackup-prod-neu-001**, uses a 180-day daily retention period — six times the standard retention applied elsewhere. No monthly or yearly retention schedules are configured alongside this, which would typically be expected if the extended retention were driven by a formal compliance requirement such as a regulatory obligation to retain specific point-in-time copies. The longer retention period is the primary reason this vault costs £69/month compared to £48/month for the equivalent UK South vault.

In addition, three vaults with names following the **CC-AZ-MIG*** pattern exist in the migration resource group. These vaults had no associated costs recorded in the February export, suggesting they are empty — but they should be confirmed as containing no protected items before deletion. The recommendation is to review whether the 180-day retention on **cc-bkpol-azvm-daily-neu-001** is tied to a specific business or compliance requirement; if not, reducing it to 30–90 days would align it with the rest of the estate and reduce GRS storage consumption. The migration vaults should be confirmed as empty and deleted.

##### Total monthly saving: £25

---

### 13. Bastion

The estate has five Bastion instances, four of which use the Developer SKU — which is provided at no charge. The fifth, **cc-bastion-prod-uks-001**, is deployed at the Standard SKU and costs £150/month. The Standard SKU provides a set of advanced features over the Basic SKU: native client and tunnelling support (enabling RDP/SSH via a native client rather than the browser), shareable links, IP-based connection, and support for multiple concurrent sessions. The Basic SKU provides browser-based RDP and SSH access at approximately £115/month — a lower cost, though still a charged tier.

If the tunnelling capability and shareable link features of the Standard SKU are not actively being used by the team connecting through **cc-bastion-prod-uks-001**, a downgrade to Basic SKU would reduce the monthly charge. This is a low-effort change that can be reversed if the Standard features are subsequently required.

##### Total monthly saving: £35

---

### 14. Orphaned Public IP Addresses

Three public IP addresses were identified during the resource inventory with no associated resource attached: **pip-apim-ecommerce-prod**, **pip-vgw-prod**, and **vnet-corp-prod-ip**. Static public IP addresses in Azure accrue a charge regardless of whether they are associated with a running resource such as a load balancer, gateway, or virtual machine. Unattached static IPs represent avoidable spend with no operational benefit.

The recommendation is straightforward: confirm that these three IP addresses are no longer required for any planned or upcoming deployment, and delete them. If any of these IPs are reserved for a specific use case and deletion would result in loss of a fixed address that cannot be recovered, this should be factored into the decision — though in most cases, a replacement static IP can be allocated if needed.

##### Total monthly saving: £31

---

### 15. Virtual Machines

Cormar Carpets operates 14 virtual machines across multiple subscriptions. Seven are corporate or shared services VMs running continuously: **CC-ADO-AGENT** (E2s_v5), **CC-AZ-COREDB01** (E4s_v5), **CC-AZ-ADC01** (D2s_v3), **CC-AZ-DC01/DC02** (F4s_v2), and **CC-AZ-LM01/LM02** (D4ds_v4). These show CPU utilisation in the 5–30% range and appropriate memory headroom for their roles; they are not right-sizing candidates at this time.

The remaining seven are sandbox developer VMs, all provisioned at **Standard_D13_v2** (8 vCPU, 56 GB RAM): **CC-DEV1-1**, **CC-DEV2-1**, **CC-DEV3-1**, **CC-DEVINT-1**, **CC-HSOTEST-1**, **CC-PROTO-1**, and **CC-SANDBOX-1**. Auto-shutdown schedules are configured on all seven, which is a positive control that reduces idle billing. Two (**CC-DEV1-1** and **CC-DEV2-1**) were deallocated at the time of the review.

Utilisation metrics for the actively running sandbox VMs over the 30-day period show an average CPU of 2.7–6.4% (business hours: 2.1–6.6%) and available memory in the range of 42–48 GB — meaning only 8–14 GB of the 56 GB provisioned capacity is being consumed. The D13_v2 SKU is a memory-intensive instance designed for workloads requiring close to 56 GB of RAM. None of the sandbox workloads are approaching that ceiling: the observed maximum memory usage across the fleet is approximately 14 GB.

The recommendation is to right-size the sandbox VMs from Standard_D13_v2 to **Standard_D8s_v3** (8 vCPU, 32 GB RAM). This maintains the same core count — avoiding any risk of CPU-bound impact — while removing 24 GB of unused RAM per VM. The D8s_v3 also benefits from premium storage support, matching the existing disk configuration. At pay-as-you-go rates, the D13_v2 costs approximately £0.60/hour versus £0.31/hour for the D8s_v3. Across the five actively running VMs at typical sandbox hours, the estimated saving is in the range of £250–300/month.

##### Total monthly saving: £275

---

## Summary Table

| Item | Potential Monthly Cost Saving | Effort to Implement |
|------|------------------------------|---------------------|
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
