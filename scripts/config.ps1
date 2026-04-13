# Suppress PSUseDeclaredVarsMoreThanAssignments — this file is dot-sourced by other scripts.
# Variables are consumed externally; PSScriptAnalyzer cannot see cross-file usage.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

# ============================================================
# FinOps Engagement — Central Configuration
# ============================================================
# Customer:  <Customer Name>
# Configured: <Date>
#
# Set all variables in this file before running any scripts.
# All PowerShell scripts dot-source this file automatically.
# KQL files do not use this config — run them in the portal.
# ============================================================

# ------------------------------------------------------------
# Subscriptions
# ------------------------------------------------------------

# All subscription IDs in scope
$allSubscriptions = @(
    # "<sub-id>",  # <Subscription Name>
)

# Prod-only subscriptions (used for Defender, security checks)
$prodSubscriptions = @(
    # "<sub-id>",  # <Subscription Name>
)

# ------------------------------------------------------------
# SQL Elastic Pools — initial 30-day screen
# Used by: phase3-utilisation/01-sql-pool-metrics.ps1
# ------------------------------------------------------------
$sqlPools = @(
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Server="<sql-server-name>"; Pool="<pool-name>"; Type="DTU" },
    # Type is either "DTU" or "vCore"
)

# ------------------------------------------------------------
# SQL Elastic Pools — 7-day 1-minute deep-dive
# Used by: phase3-utilisation/01-sql-pool-metrics-deepdive.ps1
# Populate AFTER initial screen identifies right-sizing candidates.
# ------------------------------------------------------------
$sqlPoolsDeepDive = @(
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Server="<sql-server-name>"; Pool="<pool-name>"; Type="DTU" },
)

# ------------------------------------------------------------
# App Service Plans — initial 30-day screen
# Used by: phase3-utilisation/04-app-service-metrics.ps1
# ------------------------------------------------------------
$appServicePlans = @(
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Name="<plan-name>" },
)

# ------------------------------------------------------------
# App Service Plans — 7-day 1-minute deep-dive
# Used by: phase3-utilisation/04-app-service-metrics-deepdive.ps1
# Populate AFTER initial screen identifies right-sizing candidates.
# Sku = current SKU of the plan (used to convert memory % to absolute GB)
# CandidateSku = target SKU being considered (used to show headroom check)
# ------------------------------------------------------------
$appServicePlansDeepDive = @(
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Name="<plan-name>"; Sku="P2mv3"; CandidateSku="P1v3" }
)

# ------------------------------------------------------------
# Service Bus Namespaces
# Used by: phase3-utilisation/05-servicebus-metrics.ps1
# Note: Premium namespaces require private connectivity.
#       Metric collection from outside the VNET may return zero.
# ------------------------------------------------------------
$serviceBusNamespaces = @(
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Name="<namespace-name>"; Tier="Premium" },
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Name="<namespace-name>"; Tier="Standard" },
)

# ------------------------------------------------------------
# Data Factory Instances
# Used by: phase2-inventory/12-data-factory-ir.ps1
#          phase3-utilisation/12-data-factory-pipeline-runs.ps1
# ------------------------------------------------------------
$dataFactories = @(
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Name="<factory-name>" },
)

# ------------------------------------------------------------
# Backup / Recovery Services Vaults
# Used by: phase2-inventory/16-backup-retention.ps1
# Note: ResourceMove-* vaults excluded (temporary migration artefacts)
# ------------------------------------------------------------
$backupVaults = @(
    # @{ Sub="<sub-id>"; RG="<resource-group>"; Name="<vault-name>" },
)

# ------------------------------------------------------------
# Azure Firewall
# Used by: phase2-inventory/08-azure-firewall-diagnostics.ps1
# ------------------------------------------------------------
$firewallResourceIds = @(
    # "/subscriptions/<sub-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/azureFirewalls/<firewall-name>",
)

# ------------------------------------------------------------
# Virtual WAN Hubs (check each for active traffic)
# Used by: phase3-utilisation/virtual-wan-hub-traffic.ps1
# ------------------------------------------------------------
$vwanHubResourceIds = @(
    # "/subscriptions/<sub-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualHubs/<hub-name>",
)

# ------------------------------------------------------------
# Output Directories
# Set both to the customer subfolder before running any scripts.
# $resourceDataDir — Phase 2 inventory CSVs (resource configuration)
# $outputDir       — Phase 3 metrics CSVs (utilisation data)
# ------------------------------------------------------------
$resourceDataDir = "C:\path\to\FinOps\<customer>\resource-data"
$outputDir       = "C:\path\to\FinOps\<customer>\metrics"
