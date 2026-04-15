# Snowflake Migration (Portfolio)

Migrating a legacy SQL Server + SSIS + SSAS + SSRS + Power BI BI stack to a Snowflake-native architecture on Azure. Built to enterprise standards as a Snowflake Solution Architect portfolio project.

See [CLAUDE.md](CLAUDE.md) for the full architecture, conventions, and phased roadmap.

## Repo layout

```text
terraform/   # IaC for Snowflake and Azure objects
dbt/         # dbt Core project (staging -> core -> marts)
snowpipe/    # Snowpipe definitions and quarantine patterns
airflow/     # Demo DAG (skill demo, not core orchestration)
streamlit/   # Streamlit-in-Snowflake apps (Cortex Analyst)
notebooks/   # Ad-hoc analysis and design scratchpads
data/        # Source-data inventory and sample metadata (no raw data)
```

## Prerequisites

- **Terraform** >= 1.14 - `winget install HashiCorp.Terraform`
- **Python** 3.11+ with `dbt-core` and `dbt-snowflake`
- **Azure CLI** - authenticated to subscription `60abe083-7f78-4a57-9f4f-ca0214215c77`
- **Snowflake account** - Enterprise edition in `AZURE_EASTUS`, with an RSA public key registered on the user for programmatic auth
- **PowerShell 7** or Bash (Git Bash / WSL)

## Environment setup

Copy the block below into a new file named `.env` at the repo root (`snowflake-migration/.env`). It is gitignored.

```bash
# ---- Snowflake ----
SNOWFLAKE_ACCOUNT=VNCENFN-XF07416
SNOWFLAKE_USER=LSILINDA
SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
SNOWFLAKE_PRIVATE_KEY_PATH=C:/Users/Lonwabo_Eric/.snowflake/keys/lsilinda_rsa_key.p8
SNOWFLAKE_ROLE=ACCOUNTADMIN
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
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

- `.env` is gitignored. Never commit it.
- No Snowflake password is stored. Programmatic auth uses key-pair auth (`SNOWFLAKE_JWT`).
- The private key lives outside the repo at `C:/Users/Lonwabo_Eric/.snowflake/keys/`.
- Azure subscription and tenant IDs are not secrets, but they are pinned here for reproducibility.
- Any service principal credentials added later go in `.env` only and are referenced via environment variables in Terraform.

## Current status

**Foundations** is in progress.

- Applied already: Terraform bootstrap for remote state and the shared Snowflake storage integration `SI_AZURE_FSPSFTPSOURCE_DEV`.
- Built in code but not yet applied: `ANALYTICS_DEV`, named RAW schemas, shared `STAGING`/`CORE`/`MARTS`, and the three per-company external stages plus CSV file formats.
- Current Terraform plan in `terraform/environments/dev` is clean: `13 to add, 0 to change, 0 to destroy`.
- Immediate next step: `terraform apply` in `terraform/environments/dev`, then verify stage access with `LIST @ANALYTICS_DEV.RAW_MAIN_BOOK.STG_COMPANY_01_OUTBOUND/Outbound;`.

## Current phase

**Foundations** - see [CLAUDE.md](CLAUDE.md) for the live checklist of what is done and what is next.
