# Data Factory — Integration Runtime types
# CONFIGURE: Set factories array below (get names first from Resource Graph query)
# Identifies Managed VNET IR (more expensive) vs standard Azure IR vs Self-Hosted IR

. "$PSScriptRoot\..\config.ps1"

$factories = $dataFactories

$results = foreach ($f in $factories) {
    az account set --subscription $f.sub | Out-Null
    $raw = az datafactory integration-runtime list `
        --factory-name $f.name `
        --resource-group $f.rg `
        --output json 2>&1
    if ($raw -match '^\[' -or $raw -match '^\{') {
        $irs = $raw | ConvertFrom-Json
        foreach ($ir in $irs) {
            [PSCustomObject]@{
                Factory     = $f.name
                IR          = $ir.name
                Type        = $ir.properties.type
                ManagedVNet = $ir.properties.managedVirtualNetwork.referenceName
            }
        }
    } else {
        [PSCustomObject]@{ Factory = $f.name; IR = "ERROR"; Type = ($raw | Out-String).Trim(); ManagedVNet = "" }
    }
}

$results | Format-Table -AutoSize
