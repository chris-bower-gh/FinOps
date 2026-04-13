# How to Run a FinOps Engagement

A plain-English guide for starting, running, and completing a cost optimisation engagement from scratch.

---

## What You Need Before You Start

- Azure CLI installed and working (`az --version` in a terminal to confirm)
- Read access to the customer's Azure tenant
- The customer's subscription IDs (get these from the Azure portal → Subscriptions)

---

## Step 1 — Set Up the Customer Folder

Create a new folder under `FinOps/` named after the customer:

```text
FinOps/
  [customer-name]/
    cost-exports/
    metrics/
    resource-data/
    analysis-notes/
```

Copy `scripts/config.ps1` into the customer folder and rename it — or just note that you'll edit the one in `scripts/` directly and reset it for the next customer.

---

## Step 2 — Log In to the Customer's Azure Tenant

```powershell
az login
az account list --output table   # verify you can see their subscriptions
```

Note down the subscription IDs — you'll need them in the next step.

---

## Step 3 — Fill In config.ps1

Open `scripts/config.ps1` and fill in the top sections:

```powershell
$allSubscriptions = @(
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
)

$resourceDataDir = "C:\path\to\FinOps\[customer-name]\resource-data"
$outputDir       = "C:\path\to\FinOps\[customer-name]\metrics"
```

`$resourceDataDir` is where Phase 2 PS1 scripts write their CSVs. `$outputDir` is where Phase 3 metrics scripts write theirs. Both must be set before running any PS1 script.

Leave everything else blank for now — the other sections (`$sqlPools`, `$appServicePlans`, etc.) get filled in as you go.

---

## Step 4 — Export Cost Data from the Azure Portal

For **each subscription**, do the following in the Azure portal:

1. Go to **Cost Management + Billing → Cost Analysis**
2. Set the scope to the subscription
3. Change the view to **Cost by Resource**
4. Set the date range to the **last full calendar month**
5. Set granularity to **None**
6. Click **Download → CSV**
7. Save the file to `[customer-name]/cost-exports/` with a descriptive name (e.g. `costs-prod.csv`)

> Do this for all subscriptions before moving on. Cost exports tell you where the money is — everything else follows from this.

---

## Step 5 — Start an AI Session

Open a new conversation with Claude (or any AI assistant).

Paste the entire contents of `FinOps-AI-Prompt.md` as your first message.

Then say something like:

> New customer: [Customer Name]. I have cost exports for [X] subscriptions in `[customer-name]/cost-exports/`. Let's start.

The AI will take it from there — it will tell you which scripts to run, in what order, and will work through the findings with you interactively.

---

## Step 6 — Run Scripts as Instructed

The AI will tell you exactly which scripts to run. There are two types:

**KQL scripts** (`.kql` files) — run these in the Azure portal:

1. Go to portal.azure.com → search for **Resource Graph Explorer**
2. Paste the contents of the `.kql` file
3. Click **Run query**
4. Download the results as CSV and save to `[customer-name]/resource-data/`

**PowerShell scripts** (`.ps1` files) — run these in a terminal:

1. Make sure `config.ps1` is filled in for the relevant section
2. Ensure `az login` has been completed
3. Run the script using its full path: `& "C:\path\to\FinOps\scripts\phase2-inventory\[script-name].ps1"`
4. Phase 2 scripts write CSVs to `$resourceDataDir`; Phase 3 scripts write to `$outputDir` — no manual copying needed

---

## Step 7 — Share Results with the AI

After running each script, either:

- Paste the output directly into the chat, or
- Tell the AI where the output file is saved — it can read it directly if you're using Claude Code in VS Code

The AI will analyse the results, propose findings, and ask you to confirm before writing anything into the report.

---

## Step 8 — Review and Confirm Each Finding

The AI works through findings one at a time. For each one:

- It will show you what the data says and what it recommends
- You confirm, correct, or provide additional context
- It writes the section into `report.md`

You don't need to write anything yourself — just validate the findings as you go.

---

## Step 9 — Finalise the Report

Once all findings are confirmed, the AI will produce a summary table with total savings and implementation effort. Review it, then:

1. Copy `report.md` into Word (or ask the AI to format it)
2. Add the Synextra logo and standard cover page
3. Send to the customer

---

## Reference Files (if you need to look something up)

| File | What it's for |
| --- | --- |
| `FinOps-AI-Prompt.md` | Paste this into AI at the start of every engagement |
| `FinOps-Process-Guide.md` | Detailed step-by-step technical process |
| `FinOps-Reference-Library.md` | Cost saving opportunities by Azure service type |
| `scripts/README.md` | Full list of every script and what it does |
| `scripts/engagement-methodology.md` | The three-phase methodology explained |
| `scripts/config.ps1` | Configuration file — fill this in before running any PS1 script |

---

## Folder Structure Reminder

```text
FinOps/
  HOW-TO-RUN-AN-ENGAGEMENT.md    ← you are here
  FinOps-AI-Prompt.md            ← paste into AI at start of engagement
  FinOps-Process-Guide.md        ← detailed technical process
  FinOps-Reference-Library.md    ← reference by service type
  scripts/
    config.ps1                   ← fill in before running scripts
    README.md                    ← script index
    engagement-methodology.md    ← three-phase methodology
    phase2-inventory/            ← KQL and PS1 scripts for resource data
    phase3-utilisation/          ← PS1 scripts for metrics
  [customer-name]/               ← all output for a specific engagement
    cost-exports/
    metrics/
    resource-data/
    analysis-notes/
    report.md
```
