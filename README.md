# Snowflake Migration (Portfolio)

Migrating a legacy SQL Server + SSIS + SSAS + SSRS + Power BI BI stack to a Snowflake-native architecture on Azure. Built to enterprise standards as a Snowflake Solution Architect portfolio project.

See [CLAUDE.md](CLAUDE.md) for full architecture, conventions, and phased roadmap.

## Repo layout

```
terraform/   # IaC for all Snowflake + Azure objects
dbt/         # dbt Core project (staging → core → marts)
snowpipe/    # Snowpipe definitions and quarantine patterns
airflow/     # Demo DAG (skill-demo, not core orchestration)
streamlit/   # Streamlit-in-Snowflake apps (Cortex Analyst)
notebooks/   # Ad-hoc analysis / design scratchpads
data/        # Source-data inventory and sample metadata (no raw data)
```

## Prerequisites

- **Terraform** ≥ 1.14 — `winget install HashiCorp.Terraform`
- **Python** 3.11+ with `dbt-core` and `dbt-snowflake`
- **Azure CLI** — authenticated to subscription `60abe083-7f78-4a57-9f4f-ca0214215c77`
- **Snowflake account** — Enterprise edition, `AZURE_EASTUS`, SSO-enabled user
- **PowerShell 7** or Bash (Git Bash / WSL)

## Environment setup

Copy the block below into a new file named `.env` at the repo root (`snowflake-migration/.env`). It is gitignored. Fill in any values that differ from the defaults.

```bash
# ---- Snowflake ----
SNOWFLAKE_ACCOUNT=VNCENFN-XF07416       # org-account identifier
SNOWFLAKE_USER=LSILINDA
SNOWFLAKE_AUTHENTICATOR=externalbrowser # SSO — no password stored
SNOWFLAKE_ROLE=ACCOUNTADMIN             # bootstrap only; switch to FR_ENGINEER post-RBAC
SNOWFLAKE_WAREHOUSE=COMPUTE_WH          # until LOAD_WH/TRANSFORM_WH exist
SNOWFLAKE_DATABASE=ANALYTICS_DEV
SNOWFLAKE_REGION=AZURE_EASTUS

# ---- Azure ----
AZURE_SUBSCRIPTION_ID=60abe083-7f78-4a57-9f4f-ca0214215c77
AZURE_TENANT_ID=bc5006a1-0712-4769-a24f-3cc61c360e7e
AZURE_RESOURCE_GROUP=snflk_training_rg
AZURE_STORAGE_ACCOUNT=fspsftpsource
AZURE_STORAGE_REGION=southafricanorth
AZURE_CONTAINER_COMPANY_01=fsp-company-01
AZURE_CONTAINER_COMPANY_02=fsp-company-02
AZURE_CONTAINER_COMPANY_03=fsp-company-03
```

### Secrets policy

- `.env` is gitignored — never commit it.
- No Snowflake password is stored; auth uses SSO (`externalbrowser`).
- Azure subscription/tenant IDs are not secrets but are pinned here for reproducibility.
- Any service principal credentials added later go in `.env` only, referenced via env vars in Terraform.

## Current phase

**Foundations** — see [CLAUDE.md §4](CLAUDE.md) for the live checklist of what's done and what's next.
