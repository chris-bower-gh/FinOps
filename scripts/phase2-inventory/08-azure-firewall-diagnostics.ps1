# Azure Firewall — diagnostic settings
# CONFIGURE: Set firewall resource ID below
# NOTE: Diagnostic settings are extension resources; Resource Graph does not reliably return them.
#       Use this CLI command instead.

. "$PSScriptRoot\..\config.ps1"

az monitor diagnostic-settings list --resource $firewallResourceId --output json
